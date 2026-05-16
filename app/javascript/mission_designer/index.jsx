import React from "react";
import { createRoot } from "react-dom/client";
import MissionDesigner from "./MissionDesigner";
import "../../assets/tailwind/features/_mission.css";

let root = null;

const mountDesigner = () => {
  const container = document.getElementById("mission-designer-root");
  if (!container || root) return; // already mounted or no container

  const initialNodes = JSON.parse(container.dataset.initialNodes || "[]");
  const initialEdges = JSON.parse(container.dataset.initialEdges || "[]");
  const flowDataInputId = container.dataset.flowDataInputId || "mission-flow-data";

  root = createRoot(container);
  root.render(
    <MissionDesigner
      initialNodes={initialNodes}
      initialEdges={initialEdges}
      flowDataInputId={flowDataInputId}
    />,
  );
};

const unmountDesigner = () => {
  if (root) {
    root.unmount();
    root = null;
  }
};

document.addEventListener("turbo:load", mountDesigner);
document.addEventListener("turbo:before-cache", unmountDesigner);

// Mount immediately if turbo:load already fired before this script executed
// (happens during Turbo Drive navigation when the script is loaded fresh)
mountDesigner();
