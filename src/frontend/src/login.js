import { backend } from "../../declarations/backend";

// Initialize the actor with the backend
let actor = backend;

const greetButton = document.getElementById("greet");
greetButton.onclick = async (e) => {
  e.preventDefault();
  greetButton.setAttribute("disabled", true);

  try {
    // Interact with backend actor, calling the greet method
    const principalID = await actor.whoami();

    greetButton.removeAttribute("disabled");
    document.getElementById("greeting").innerText = principalID;
    console.log("principalID: ", principalID);
  } catch (error) {
    console.error("Error fetching principal ID: ", error);
    greetButton.removeAttribute("disabled");
  }

  return false;
};