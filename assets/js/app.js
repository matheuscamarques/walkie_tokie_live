// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";

let Hooks = {};
Hooks.MicButton = {
  mounted() {
    this.el.addEventListener("mousedown", () => {
      this.pushEvent("start_transmission");
    });
    this.el.addEventListener("mouseup", () => {
      this.pushEvent("stop_transmission");
    });
    this.el.addEventListener("mouseleave", () => {
      this.pushEvent("stop_transmission");
    });
    this.el.addEventListener("touchstart", () => {
      this.pushEvent("start_transmission");
    });

    this.el.addEventListener("mouseenter", () => {
      this.pushEvent("start_transmission");
    });

    this.el.addEventListener("touchend", () => {
      this.pushEvent("stop_transmission");
    });

   
  },
};

let granted = false;
Hooks.PushNotification = {
  mounted() {
    if (!("Notification" in window)) {
      console.log("Este navegador não suporta notificações de desktop.");
      return;
    }

    Notification.requestPermission().then((permission) => {
      granted = permission === "granted";
      if (granted) {
        console.log("Permissão para notificações concedida!");
      } else if (permission === "denied") {
        console.log("Permissão para notificações negada pelo usuário.");
      } else if (permission === "default") {
        console.log("O usuário ainda não respondeu ao pedido de permissão.");
      }
    });

    this.handleEvent("push-notification", ({ title, body }) => {
      console.log("hello")
      if (granted) {
        new Notification(title, { body });
      } else if (Notification.permission !== "denied") {
        console.log("Notificação não exibida porque a permissão não foi concedida.");
      }
    });
  },
};

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
  
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker
      .register("/service-worker.js")
      .then((registration) => {
        console.log("Service Worker registrado com sucesso:", registration);
      })
      .catch((error) => {
        console.log("Erro ao registrar o Service Worker:", error);
      });
  });
}