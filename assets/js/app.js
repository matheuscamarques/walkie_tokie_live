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

Hooks.MessageInput = {
  mounted() {
    this.el.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        const message = this.el.value;
        if (message.trim() !== "") {
          this.pushEvent("send_message", { message });
          this.el.value = "";
        }
      }
    });
  }
}

Hooks.WebcamButton = {
  mounted() {
    this.localStream = null;
    this.peerConnections = {};
    this.cameraActive = false;
    this.myNodeId = this.el.dataset.nodeId;

    this.el.addEventListener("click", () => {
      this.toggleCamera();
    });

    // Another user changed camera status
    this.handleEvent("camera_status_change", ({ node, active }) => {
      if (node === this.myNodeId) return;
      if (active) {
        this.initiateConnection(node);
      } else {
        this.closePeerConnection(node);
        this.removeRemoteVideo(node);
      }
    });

    // WebRTC signaling relayed from server
    this.handleEvent("webrtc_signal", ({ from, type, data }) => {
      const parsed = JSON.parse(data);
      if (type === "offer") {
        this.handleOffer(from, parsed);
      } else if (type === "answer") {
        const pc = this.peerConnections[from];
        if (pc) pc.setRemoteDescription(new RTCSessionDescription(parsed)).catch(console.error);
      } else if (type === "ice") {
        const pc = this.peerConnections[from];
        if (pc) pc.addIceCandidate(new RTCIceCandidate(parsed)).catch(console.error);
      }
    });
  },

  async toggleCamera() {
    if (this.cameraActive) {
      if (this.localStream) {
        this.localStream.getTracks().forEach(t => t.stop());
        this.localStream = null;
      }
      Object.keys(this.peerConnections).forEach(nodeId => this.closePeerConnection(nodeId));
      this.cameraActive = false;
      this.pushEvent("toggle_camera", { active: false });
      const localVideo = document.getElementById("local-video");
      if (localVideo) localVideo.srcObject = null;
    } else {
      try {
        this.localStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
        this.cameraActive = true;
        this.pushEvent("toggle_camera", { active: true });
        const localVideo = document.getElementById("local-video");
        if (localVideo) localVideo.srcObject = this.localStream;
      } catch (err) {
        console.error("Error accessing camera:", err);
        alert("Could not access camera: " + err.message);
      }
    }
  },

  // Viewer initiates a connection to receive the broadcaster's stream
  async initiateConnection(broadcasterId) {
    const pc = this.createPeerConnection(broadcasterId);
    pc.addTransceiver("video", { direction: "recvonly" });
    try {
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      this.pushEvent("webrtc_signal", {
        target: broadcasterId,
        type: "offer",
        data: JSON.stringify(offer)
      });
    } catch (err) {
      console.error("Error creating offer:", err);
    }
  },

  // Broadcaster handles an incoming offer from a viewer
  async handleOffer(viewerId, offer) {
    const pc = this.createPeerConnection(viewerId);
    if (this.localStream) {
      this.localStream.getTracks().forEach(track => pc.addTrack(track, this.localStream));
    }
    try {
      await pc.setRemoteDescription(new RTCSessionDescription(offer));
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      this.pushEvent("webrtc_signal", {
        target: viewerId,
        type: "answer",
        data: JSON.stringify(answer)
      });
    } catch (err) {
      console.error("Error handling offer:", err);
    }
  },

  createPeerConnection(nodeId) {
    if (this.peerConnections[nodeId]) {
      this.peerConnections[nodeId].close();
    }
    const pc = new RTCPeerConnection({
      iceServers: [
        { urls: "stun:stun.l.google.com:19302" },
        { urls: "stun:stun1.l.google.com:19302" }
      ]
    });
    this.peerConnections[nodeId] = pc;
    pc.onicecandidate = (e) => {
      if (e.candidate) {
        this.pushEvent("webrtc_signal", {
          target: nodeId,
          type: "ice",
          data: JSON.stringify(e.candidate)
        });
      }
    };
    pc.ontrack = (e) => {
      if (e.streams && e.streams[0]) {
        this.showRemoteVideo(nodeId, e.streams[0]);
      }
    };
    pc.onconnectionstatechange = () => {
      if (pc.connectionState === "disconnected" || pc.connectionState === "failed") {
        this.closePeerConnection(nodeId);
        this.removeRemoteVideo(nodeId);
      }
    };
    return pc;
  },

  closePeerConnection(nodeId) {
    if (this.peerConnections[nodeId]) {
      this.peerConnections[nodeId].close();
      delete this.peerConnections[nodeId];
    }
  },

  showRemoteVideo(nodeId, stream) {
    const safeId = nodeId.replace(/[@.:]/g, "-");
    const container = document.getElementById("video-streams");
    if (!container) return;
    let wrapper = document.getElementById(`video-wrapper-${safeId}`);
    if (!wrapper) {
      wrapper = document.createElement("div");
      wrapper.id = `video-wrapper-${safeId}`;
      wrapper.className = "relative rounded-lg overflow-hidden bg-black aspect-video";
      const videoEl = document.createElement("video");
      videoEl.id = `remote-video-${safeId}`;
      videoEl.autoplay = true;
      videoEl.playsInline = true;
      videoEl.className = "w-full h-full object-cover";
      const label = document.createElement("div");
      label.className = "absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/70 p-2 text-white text-xs font-medium truncate";
      label.textContent = nodeId;
      wrapper.appendChild(videoEl);
      wrapper.appendChild(label);
      container.appendChild(wrapper);
    }
    const videoEl = document.getElementById(`remote-video-${safeId}`);
    if (videoEl) videoEl.srcObject = stream;
  },

  removeRemoteVideo(nodeId) {
    const safeId = nodeId.replace(/[@.:]/g, "-");
    const wrapper = document.getElementById(`video-wrapper-${safeId}`);
    if (wrapper) wrapper.remove();
  }
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