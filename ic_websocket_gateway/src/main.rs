use async_trait::async_trait;
use candid::CandidType;
use ed25519_compact::Signature;
use ezsockets::{Error, Server, Socket};
use ic_agent::{export::Principal, identity::BasicIdentity, Agent};
use serde::{Deserialize, Serialize};
use serde_cbor::{from_slice, to_vec};
use std::{
    collections::HashMap,
    net::SocketAddr,
    sync::{Arc, Mutex},
    time::Duration,
};

mod canister_methods;
mod session_store;
use session_store::{RedisSessionStore, SessionData};
use std::env;

type SessionID = u64;
type Session = ezsockets::Session<SessionID, ()>;

// url for local testing
// for local testing also the agent needs to fetch the root key
const URL: &str = "http://127.0.0.1:4943";
const FETCH_KEY: bool = true;

// url for mainnet
// const URL: &str = "https://ic0.app";
// const FETCH_KEY: bool = false;

#[derive(CandidType, Clone, Deserialize, Serialize, Eq, PartialEq, Debug)]
#[candid_path("ic_cdk::export::candid")]
struct FirstMessageFromClient {
    #[serde(with = "serde_bytes")]
    client_canister_id: Vec<u8>,
    #[serde(with = "serde_bytes")]
    sig: Vec<u8>,
}

#[derive(CandidType, Clone, Deserialize, Serialize, Eq, PartialEq, Debug)]
#[candid_path("ic_cdk::export::candid")]
struct ClientCanisterId {
    client_id: u64,
    canister_id: String,
}

#[derive(Debug)]
struct GatewaySession {
    id: SessionID,
    handle: Session,
    server_handle: Server<GatewayServer>,
    agent: Agent,

    canister_connected: bool,
    client_id: Option<u64>,
    canister_id: Option<Principal>,
    session_store: RedisSessionStore,
}

#[async_trait]
impl ezsockets::SessionExt for GatewaySession {
    type ID = SessionID;
    type Args = ();
    type Params = ();

    fn id(&self) -> &Self::ID {
        &self.id
    }

    async fn text(&mut self, _text: String) -> Result<(), Error> {
        unimplemented!()
    }

    async fn binary(&mut self, bytes: Vec<u8>) -> Result<(), Error> {
        if !self.canister_connected {
            println!("First message from client.");
            let m: FirstMessageFromClient = from_slice(&bytes).unwrap();
            let content: ClientCanisterId = from_slice(&m.client_canister_id).unwrap();
            let canister_id = Principal::from_text(&content.canister_id).unwrap();

            let client_key =
                canister_methods::ws_get_client_key(&self.agent, &canister_id, content.client_id)
                    .await;
            let sig = Signature::from_slice(&m.sig).unwrap();
            let valid = client_key.verify(&m.client_canister_id, &sig);

            match valid {
                Ok(_) => {
                    self.canister_connected = true;
                    self.client_id = Some(content.client_id);
                    self.canister_id = Some(canister_id);

                    // Store session in Redis
                    let session_data = SessionData {
                        client_id: content.client_id,
                        canister_id: content.canister_id.clone(),
                        timestamp: std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap()
                            .as_secs(),
                    };

                    if let Err(e) = self.session_store.save_session(
                        content.client_id, 
                        &session_data
                    ).await {
                        eprintln!("Failed to save session: {}", e);
                    }

                    self.server_handle.call(ConnectCanister {
                        session_id: self.id,
                        session: self.handle.clone(),
                        canister_id: content.canister_id,
                        canister_client_id: content.client_id,
                    });

                    let response = canister_methods::ws_open(
                        &self.agent,
                        &canister_id,
                        m.client_canister_id,
                        m.sig,
                    ).await;
                    println!("ws_open response when open() called: {}", response);
                    self.handle.text(response);
                }
                Err(_) => {
                    println!("Client's signature does not verify.");
                    self.handle.text("{\"status\": \"error\", \"message\": \"Invalid signature\"}".to_string());
                }
            }
        } else {
            println!(
                "Message from client #{}",
                self.client_id.unwrap()
            );
            match canister_methods::ws_message(
                &self.agent,
                &self.canister_id.unwrap(),
                bytes,
            ).await {
                Ok(response) => {
                    println!("ws_message response: {}", response);
                    self.handle.text(response);
                }
                Err(e) => {
                    eprintln!("Error sending message: {}", e);
                    self.handle.text(format!("{{\"status\": \"error\", \"message\": \"{}\"}}", e));
                }
            }
        }
        Ok(())
    }

    async fn call(&mut self, params: ()) -> Result<(), Error> {
        let () = params;
        Ok(())
    }
}

#[derive(Debug)]
struct ConnectCanister {
    session_id: u64,
    session: Session,
    canister_id: String,
    canister_client_id: u64,
}

#[derive(Debug)]
struct CanisterPoller {
    canister_id: String,
    canister_client_session_map: Arc<Mutex<HashMap<u64, Session>>>,
    identity: Arc<BasicIdentity>,
}

#[derive(CandidType, Clone, Deserialize, Serialize, Eq, PartialEq)]
pub struct CertMessage {
    pub key: String,
    #[serde(with = "serde_bytes")]
    pub val: Vec<u8>,
    #[serde(with = "serde_bytes")]
    pub cert: Vec<u8>,
    #[serde(with = "serde_bytes")]
    pub tree: Vec<u8>,
}

impl CanisterPoller {
    async fn run_polling(&self) {
        println!("Start of polling.");
        let can_map = Arc::clone(&self.canister_client_session_map);
        let agent = match canister_methods::get_new_agent(URL, self.identity.clone(), FETCH_KEY).await {
            Ok(a) => a,
            Err(e) => {
                eprintln!("Failed to create agent: {}", e);
                return;
            }
        };
        let canister_id = Principal::from_text(&self.canister_id).unwrap();
        tokio::spawn({
            let interval = Duration::from_millis(200);
            let mut nonce: u64 = 0;
            async move {
                loop {
                    let msgs = canister_methods::ws_get_messages(&agent, &canister_id, nonce).await;

                    for encoded_message in msgs.messages {
                        let client_id = encoded_message.client_id;

                        println!(
                            "Message to client #{} with key {}.",
                            client_id, encoded_message.key
                        );

                        let map = can_map.lock().unwrap();
                        if let Some(s) = map.get(&client_id) {
                            let m = CertMessage {
                                key: encoded_message.key.clone(),
                                val: encoded_message.val,
                                cert: msgs.cert.clone(),
                                tree: msgs.tree.clone(),
                            };

                            if s.alive() {
                                s.binary(to_vec(&m).unwrap());
                            }
                        } else {
                            println!("No session found for client {}", client_id);
                        }

                        nonce = encoded_message
                            .key
                            .split('_')
                            .last()
                            .unwrap()
                            .parse()
                            .unwrap();
                        nonce += 1;
                    }

                    tokio::time::sleep(interval).await;
                }
            }
        });
    }

    fn add_session(&self, canister_client_id: u64, session: Session) {
        let map = &self.canister_client_session_map;
        let mut m = map.lock().unwrap();
        m.insert(canister_client_id, session);
    }
}

#[derive(Debug)]
struct GatewayServer {
    next_session_id: u64,
    handle: Server<Self>,
    connected_canisters: HashMap<String, CanisterPoller>,
    identity: Arc<BasicIdentity>,
    close_args: HashMap<SessionID, ClientCanisterId>,
    agent: Agent,
    session_store: RedisSessionStore,
}

#[async_trait]
impl ezsockets::ServerExt for GatewayServer {
    type Params = ConnectCanister;
    type Session = GatewaySession;

    async fn accept(
        &mut self,
        socket: Socket,
        _address: SocketAddr,
        _args: (),
    ) -> Result<Session, Error> {
        let id = self.next_session_id;
        self.next_session_id += 1;
        println!("Client connected.");
        let agent = canister_methods::get_new_agent(URL, self.identity.clone(), FETCH_KEY)
            .await
            .expect("Failed to create agent");
        println!("Agent created.");

        let session = Session::create(
            |handle| GatewaySession {
                id,
                handle,
                server_handle: self.handle.clone(),
                agent,
                canister_connected: false,
                client_id: None,
                canister_id: None,
                session_store: self.session_store.clone(),
            },
            id,
            socket,
        );
        println!("Session created.");
        println!("Session ID: {}", id);

        Ok(session)
    }

    async fn disconnected(
        &mut self,
        id: <Self::Session as ezsockets::SessionExt>::ID,
    ) -> Result<(), Error> {
        if let Some(close_args) = self.close_args.remove(&id) {
            // Remove session from Redis
            if let Err(e) = self.session_store.remove_session(close_args.client_id).await {
                eprintln!("Failed to remove session: {}", e);
            }
            
            println!("Websocket with client #{} closed.", close_args.client_id);
            let canister_id = Principal::from_text(&close_args.canister_id).unwrap();
            canister_methods::ws_close(&self.agent, &canister_id, close_args.client_id).await;
        }
        Ok(())
    }

    async fn call(&mut self, add_canister: Self::Params) -> Result<(), Error> {
        let canister_id = add_canister.canister_id;
        let session = add_canister.session;
        let canister_client_id = add_canister.canister_client_id;

        self.close_args.insert(
            add_canister.session_id,
            ClientCanisterId {
                client_id: canister_client_id,
                canister_id: canister_id.clone(),
            },
        );

        match self.connected_canisters.get_mut(&canister_id) {
            None => {
                let identity = self.identity.clone();
                let poller = CanisterPoller {
                    canister_id: canister_id.clone(),
                    canister_client_session_map: Arc::new(Mutex::new(HashMap::new())),
                    identity,
                };
                poller.add_session(canister_client_id, session);
                poller.run_polling().await;
                self.connected_canisters.insert(canister_id, poller);
            }
            Some(poller) => {
                poller.add_session(canister_client_id, session);
            }
        }

        Ok(())
    }
}

#[tokio::main(flavor = "multi_thread", worker_threads = 10)]
async fn main() {
    let rng = ring::rand::SystemRandom::new();
    let key_pair = ring::signature::Ed25519KeyPair::generate_pkcs8(&rng)
        .expect("Could not generate a key pair.");
    let identity = BasicIdentity::from_key_pair(
        ring::signature::Ed25519KeyPair::from_pkcs8(key_pair.as_ref())
            .expect("Could not read the key pair."),
    );
    let identity = Arc::new(identity);
    let agent = match canister_methods::get_new_agent(URL, identity.clone(), FETCH_KEY).await {
        Ok(a) => a,
        Err(e) => {
            eprintln!("Failed to create agent: {}", e);
            std::process::exit(1);
        }
    };

    // Make sure dfx is running
    match agent.fetch_root_key().await {
        Ok(_) => println!("Connected to IC replica"),
        Err(e) => {
            eprintln!("Failed to connect to IC replica: {}. Make sure dfx is running.", e);
            std::process::exit(1);
        }
    };

    // Get Redis URL from env or use default
    let redis_url = env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    
    // Initialize Redis session store
    let session_store = RedisSessionStore::new(&redis_url)
        .expect("Failed to connect to Redis");

    let (server, _) = Server::create(|handle| GatewayServer {
        next_session_id: 0,
        handle,
        connected_canisters: HashMap::new(),
        identity,
        close_args: HashMap::new(),
        agent,
        session_store,
    });
    ezsockets::tungstenite::run(server, "127.0.0.1:8080", |_| async move { Ok(()) })
        .await
        .unwrap();
}
