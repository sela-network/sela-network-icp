import { backend } from "../../declarations/backend";

// Initialize the actor with the backend
let actor = backend;

const dataButton = document.getElementById("getData");
dataButton.onclick = async (e) => {
  e.preventDefault();
  dataButton.setAttribute("disabled", true);

  try {
    // Interact with backend actor, calling the getData method
    const principalID = await actor.whoami();

    dataButton.removeAttribute("disabled");
    document.getElementById("getData").innerText = principalID;
    console.log("principalID: ", principalID);
  } catch (error) {
    console.error("Error fetching principal ID: ", error);
    dataButton.removeAttribute("disabled");
  }

  return false;
};