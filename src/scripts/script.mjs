import { backend_code } from "./actor.mjs";

backend_code.whoami().then((result) => {
  console.log(result);
});