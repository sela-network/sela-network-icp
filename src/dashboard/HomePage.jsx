import React, { useEffect, useState } from 'react';
import { useAuth } from './use-auth-client';

import { Nav, Spacing, Header, Text } from './component';
import Color from './style/Color';
import { Dashboard, RewardHistory, RewardProgram } from './pages';

import { Layout, Modal, Avatar, Button } from 'antd';
const { Content } = Layout;

const HomePage = () => {
  const menuItems = [
    { leftIcon: 'sela', text: 'Dashboard', children: <Dashboard /> },
    {
      leftIcon: 'history',
      text: 'Reward History',
      children: <RewardHistory />,
    },
    { leftIcon: 'gift', text: 'Reward Program', children: <RewardProgram /> },
  ];

  const [selectedMenu, setSelectedMenu] = useState(menuItems[1]);
  const { whoamiActor, logout } = useAuth();
  const [principalId, setPrincipalId] = useState(null);
  const [showProfileMenu, setShowProfileMenu] = useState(false);

  useEffect(() => {
    const getPrincipalId = async () => {
      const whoami = await whoamiActor.whoami();
      setPrincipalId(whoami);
    };

    // Call the async function
    getPrincipalId();
  }, []);

  const handleMenuClick = (menu) => {
    setSelectedMenu(menu);
  };

  const setProfileMenu = () => {
    setShowProfileMenu(!showProfileMenu);
  };

  return (
    <>
      <Layout style={{ minHeight: '100vh' }}>
        <Nav
          menuItems={menuItems}
          onMenuClick={handleMenuClick}
          selectedMenu={selectedMenu}
        />

        <Layout style={{ background: '#000', marginLeft: 350 }}>
          <Content
            style={{
              padding: '20px',
              overflow: 'auto', // Allows scrolling when content is too large
            }}
          >
            <div
              style={{
                width: '100%',
                height: '2000px',
                marginTop: 35,
                textAlign: 'left',
              }}
            >
              {' '}
              <Header
                title={selectedMenu.text}
                principalId={principalId}
                setProfileMenu={setProfileMenu}
              />
              <Modal
                open={showProfileMenu}
                onCancel={() => setShowProfileMenu(false)}
                footer={null}
                closable={false}
                style={{
                  position: 'absolute',
                  top: 100,
                  right: 24,
                  borderRadius: 30,
                }}
                width={333}
                height={382}
              >
                <div
                  style={{
                    padding: 12,
                    display: 'flex',
                    justifyContent: 'center',
                    alignItems: 'center',
                    flexDirection: 'column',
                  }}
                >
                  <Avatar
                    style={{
                      backgroundColor: Color.semiGray,
                    }}
                    size={48}
                  >
                    <Text children="A" size={18} weight="semiBold" />
                  </Avatar>
                  <Spacing margin={16} />
                  <Text
                    children={'User ID'}
                    size={18}
                    color="#000"
                    weight="semiBold"
                  />
                  <Spacing margin={16} />
                  <Button
                    shape="round"
                    size={16}
                    style={{
                      backgroundColor: '#000',
                      borderColor: '#000',
                      width: 301,
                      height: 52,
                    }}
                  >
                    <Text
                      children={'Wallet Connect'}
                      size={16}
                      weight="semiBold"
                    />
                  </Button>
                  <Spacing margin={16} />
                  <Text
                    children={'Logout'}
                    size={16}
                    color="#000"
                    weight="semiBold"
                    decoration="underline"
                    onClick={logout}
                  />
                  <Spacing margin={16} />
                  <Text
                    children={'Delete Account'}
                    size={16}
                    color="#000"
                    weight="semiBold"
                    decoration="underline"
                  />
                </div>
              </Modal>
              <Spacing margin={32} />
              {selectedMenu.children}
            </div>
          </Content>
        </Layout>
      </Layout>
    </>
  );
};

export default HomePage;
