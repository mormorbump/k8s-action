// k8s-action archviz: クラスタのスナップショット (data.json) を 3D シーンとして描画する。
//
// 表現の対応:
//   大プラットフォーム      = GKE クラスタ
//   色付きの島             = namespace（枠の色 = istio-injection 有効）
//   箱                    = Pod（色 = 状態、青いチップ = istio-proxy sidecar）
//   箱の足元のストライプ     = 配置ノード
//   紫の曲線 + 流れる粒子   = トラフィック（VirtualService 由来）
//   左奥の球               = インターネット / 黄色い柱 = Cloud Load Balancer
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { CSS2DRenderer, CSS2DObject } from 'three/addons/renderers/CSS2DRenderer.js';

// ----------------------------------------------------------------------
// 基本セットアップ
// ----------------------------------------------------------------------
const container = document.getElementById('scene');

let renderer;
try {
  renderer = new THREE.WebGLRenderer({ antialias: true });
} catch (e) {
  document.getElementById('meta').textContent = `WebGL を初期化できません: ${e.message}`;
  throw e;
}
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setSize(innerWidth, innerHeight);
renderer.outputColorSpace = THREE.SRGBColorSpace;
container.appendChild(renderer.domElement);

const labelRenderer = new CSS2DRenderer();
labelRenderer.setSize(innerWidth, innerHeight);
labelRenderer.domElement.style.position = 'fixed';
labelRenderer.domElement.style.inset = '0';
labelRenderer.domElement.style.pointerEvents = 'none';
container.appendChild(labelRenderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x070a12);
scene.fog = new THREE.Fog(0x070a12, 55, 120);

const camera = new THREE.PerspectiveCamera(50, innerWidth / innerHeight, 0.1, 300);
camera.position.set(14, 16, 26);

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.08;
controls.maxPolarAngle = Math.PI * 0.49;
controls.minDistance = 8;
controls.maxDistance = 80;

scene.add(new THREE.AmbientLight(0x8090b0, 0.9));
const key = new THREE.DirectionalLight(0xffffff, 1.6);
key.position.set(12, 24, 10);
scene.add(key);
const rim = new THREE.DirectionalLight(0x6ea8ff, 0.5);
rim.position.set(-16, 10, -14);
scene.add(rim);

const grid = new THREE.GridHelper(160, 80, 0x1c2742, 0x131a2c);
grid.position.y = -0.51;
scene.add(grid);

// ----------------------------------------------------------------------
// ユーティリティ
// ----------------------------------------------------------------------
const POD = { w: 0.85, h: 0.55, gap: 1.25 };
const nsPalette = [0x2f6fed, 0x9a6bff, 0x00b8a9, 0xff8a3d, 0xe554a4, 0x49c0ff, 0xb8c34a];
const nodeStripe = [0xffd166, 0x06d6a0, 0xef476f, 0x118ab2];

function makeLabel(text, cls, y = 0) {
  const div = document.createElement('div');
  div.className = cls;
  div.textContent = text;
  const obj = new CSS2DObject(div);
  obj.position.set(0, y, 0);
  return obj;
}

function podColor(p) {
  if (p.phase === 'Failed') return 0xff5d5d;
  if (p.phase !== 'Running' || p.ready < p.total) return 0xffc24b;
  return 0x39d98a;
}

// namespace の表示順: インフラ系 → アプリ → プレビュー
function nsOrder(name) {
  const order = ['istio-system', 'istio-ingress', 'cert-manager', 'argocd', 'baseline', 'default'];
  const i = order.indexOf(name);
  if (i >= 0) return i;
  if (name.startsWith('preview-')) return 50;
  return 20;
}

// VS destination host → namespace（短縮名は VS 自身の ns に解決される: ADR-0003）
function destNamespace(host, vsNamespace) {
  const m = host.match(/^[^.]+\.([^.]+)\.svc\.cluster\.local$/);
  if (m) return m[1];
  if (!host.includes('.')) return vsNamespace;
  return null; // 外部ホスト等
}

// ----------------------------------------------------------------------
// シーン構築
// ----------------------------------------------------------------------
const pickables = []; // raycast 対象
const flows = [];     // {curve, dots:[{mesh, t}]}

function buildScene(data) {
  document.getElementById('meta').textContent =
    `cluster: ${data.cluster} / ${data.pods.length} pods / snapshot: ${data.generatedAt}`;

  const namespaces = [...data.namespaces].sort((a, b) => nsOrder(a.name) - nsOrder(b.name));
  const nodeIndex = new Map(data.nodes.map((n, i) => [n.name, i]));

  // --- namespace 島のレイアウト（横一列、必要幅で詰める） ---
  const islands = new Map(); // ns name → {cx, cz, w, d}
  let cursorX = 0;
  const islandGroup = new THREE.Group();
  scene.add(islandGroup);

  const boxGeo = new THREE.BoxGeometry(POD.w, POD.h, POD.w);
  const chipGeo = new THREE.BoxGeometry(POD.w * 0.95, POD.h * 0.3, 0.1);
  const stripeGeo = new THREE.BoxGeometry(POD.w, 0.07, POD.w);

  namespaces.forEach((ns, idx) => {
    const pods = data.pods.filter((p) => p.namespace === ns.name);
    const cols = Math.max(1, Math.ceil(Math.sqrt(pods.length || 1)));
    const rows = Math.max(1, Math.ceil((pods.length || 1) / cols));
    const w = cols * POD.gap + 1.2;
    const d = rows * POD.gap + 1.2;
    const cx = cursorX + w / 2;
    cursorX += w + 1.6;
    islands.set(ns.name, { cx, cz: 0, w, d });

    const color = nsPalette[idx % nsPalette.length];

    // 島スラブ
    const slab = new THREE.Mesh(
      new THREE.BoxGeometry(w, 0.3, d),
      new THREE.MeshStandardMaterial({ color, transparent: true, opacity: 0.22, roughness: 0.6 })
    );
    slab.position.set(cx, 0.15, 0);
    islandGroup.add(slab);

    // injection 有効 namespace は枠線で示す
    const edge = new THREE.LineSegments(
      new THREE.EdgesGeometry(slab.geometry),
      new THREE.LineBasicMaterial({
        color: ns.injection === 'enabled' ? 0x4f8dff : 0x2a3550,
        transparent: true, opacity: 0.9,
      })
    );
    slab.add(edge);

    const lbl = makeLabel(
      ns.injection === 'enabled' ? `${ns.name} ⛴` : ns.name, 'ns-label', 0
    );
    lbl.position.set(0, 0.7, d / 2 + 0.55);
    slab.add(lbl);

    // Pod
    pods.forEach((p, i) => {
      const col = i % cols, row = Math.floor(i / cols);
      const px = cx - ((cols - 1) * POD.gap) / 2 + col * POD.gap;
      const pz = -((rows - 1) * POD.gap) / 2 + row * POD.gap;

      const mesh = new THREE.Mesh(
        boxGeo,
        new THREE.MeshStandardMaterial({ color: podColor(p), roughness: 0.45 })
      );
      mesh.position.set(px, 0.3 + POD.h / 2, pz);
      mesh.userData = { kind: 'Pod', ...p };
      islandGroup.add(mesh);
      pickables.push(mesh);

      if (p.hasSidecar) {
        const chip = new THREE.Mesh(
          chipGeo,
          new THREE.MeshStandardMaterial({ color: 0x4f8dff, roughness: 0.4 })
        );
        chip.position.set(0, -POD.h * 0.2, POD.w / 2 + 0.06);
        mesh.add(chip);
      }
      const ni = nodeIndex.get(p.node);
      if (ni !== undefined) {
        const stripe = new THREE.Mesh(
          stripeGeo,
          new THREE.MeshStandardMaterial({ color: nodeStripe[ni % nodeStripe.length] })
        );
        stripe.position.y = -POD.h / 2 - 0.05;
        mesh.add(stripe);
      }
    });
  });

  // 中央寄せ
  const totalW = cursorX - 1.6;
  islandGroup.position.x = -totalW / 2;
  const islandCenter = (name) => {
    const isl = islands.get(name);
    return isl ? new THREE.Vector3(isl.cx - totalW / 2, 0.6, isl.cz) : null;
  };

  // シーン全体が収まるようカメラを自動フレーミング
  const dist = Math.max(20, totalW * 0.78);
  camera.position.set(0, dist * 0.5, dist * 0.82);
  controls.target.set(-totalW * 0.1, 0.5, 0); // Internet/LB のある左側も収める
  controls.update();

  // --- GKE クラスタプラットフォーム ---
  const platform = new THREE.Mesh(
    new THREE.BoxGeometry(totalW + 4, 0.5, 14),
    new THREE.MeshStandardMaterial({ color: 0x101a30, roughness: 0.85 })
  );
  platform.position.y = -0.25;
  scene.add(platform);
  const platformLabel = makeLabel(`GKE cluster: ${data.cluster}`, 'ns-label');
  platformLabel.position.set(-totalW / 2 - 0.5, 0.25, 7.6);
  platform.add(platformLabel);

  // --- ノード（奥にスラブとして配置、ストライプ色と対応） ---
  data.nodes.forEach((n, i) => {
    const slab = new THREE.Mesh(
      new THREE.BoxGeometry(7, 0.5, 2.4),
      new THREE.MeshStandardMaterial({
        color: nodeStripe[i % nodeStripe.length], transparent: true, opacity: 0.35,
      })
    );
    slab.position.set(-totalW / 2 + 4 + i * 8, 0.3, -9.5);
    slab.userData = { kind: 'Node', ...n };
    scene.add(slab);
    pickables.push(slab);
    const lbl = makeLabel(`${n.name.replace(/^gke-.*-default-/, 'node: ')} (${n.instanceType})`, 'obj-label');
    lbl.position.set(0, 0.7, 0);
    slab.add(lbl);
  });

  // --- インターネット → LB → Ingress Gateway ---
  const lbSvc = data.services.find((s) => s.externalIP);
  const gwNs = data.pods.find((p) => p.app === 'istio-ingressgateway')?.namespace;
  const gwPos = gwNs ? islandCenter(gwNs) : null;

  const inet = new THREE.Mesh(
    new THREE.SphereGeometry(1.5, 32, 24),
    new THREE.MeshStandardMaterial({
      color: 0x1c2742, roughness: 0.3, emissive: 0x4f8dff, emissiveIntensity: 0.25,
    })
  );
  const inetX = -totalW / 2 - 13;
  inet.position.set(inetX, 4.5, 4);
  scene.add(inet);
  inet.add(makeLabel('Internet', 'ns-label', 2.3));

  if (lbSvc && gwPos) {
    const lb = new THREE.Mesh(
      new THREE.CylinderGeometry(0.5, 0.7, 2.6, 6),
      new THREE.MeshStandardMaterial({ color: 0xffd166, roughness: 0.4 })
    );
    lb.position.set(inetX + 6.5, 1.3, 2.5);
    lb.userData = { kind: 'LoadBalancer', name: lbSvc.name, namespace: lbSvc.namespace, externalIP: lbSvc.externalIP };
    scene.add(lb);
    pickables.push(lb);
    lb.add(makeLabel(`Cloud LB ${lbSvc.externalIP}`, 'obj-label', 1.9));

    addFlow([inet.position, lb.position.clone().add(new THREE.Vector3(0, 1, 0)), gwPos], 0x9a6bff);
  }

  // --- VirtualService からトラフィックエッジを張る ---
  data.virtualservices.forEach((vs) => {
    const isGatewayBound = vs.gateways.some((g) => !g.includes('mesh'));
    (vs.destinations || []).forEach((dest) => {
      const destNs = destNamespace(dest, vs.namespace);
      if (!destNs) return;
      const to = islandCenter(destNs);
      if (!to) return;

      if (isGatewayBound && gwPos) {
        if (to.distanceTo(gwPos) < 0.1) return;
        const mid = gwPos.clone().lerp(to, 0.5); mid.y += 2.2 + Math.random() * 1.2;
        addFlow([gwPos, mid, to], 0x9a6bff, vs.hosts[0]);
      } else {
        // メッシュ内 VS（スイムレーン等）: VS の ns → 宛先 ns
        const from = islandCenter(vs.namespace);
        if (!from || from.distanceTo(to) < 0.1) return;
        const mid = from.clone().lerp(to, 0.5); mid.y += 1.6;
        addFlow([from, mid, to], 0x00b8a9, `${vs.name} (mesh)`);
      }
    });
  });
}

function addFlow(points, color, labelText) {
  const curve = new THREE.CatmullRomCurve3(points.map((p) => p.clone()));
  const tube = new THREE.Mesh(
    new THREE.TubeGeometry(curve, 48, 0.045, 6, false),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.3 })
  );
  scene.add(tube);

  const dotGeo = new THREE.SphereGeometry(0.13, 10, 8);
  const dotMat = new THREE.MeshBasicMaterial({ color });
  const dots = Array.from({ length: 3 }, (_, i) => {
    const mesh = new THREE.Mesh(dotGeo, dotMat);
    scene.add(mesh);
    return { mesh, t: i / 3 };
  });
  flows.push({ curve, dots });

  if (labelText) {
    const lbl = makeLabel(labelText, 'obj-label');
    const mid = curve.getPoint(0.5);
    lbl.position.copy(mid).add(new THREE.Vector3(0, 0.45, 0));
    scene.add(lbl);
  }
}

// ----------------------------------------------------------------------
// ホバー詳細（DOM HUD）
// ----------------------------------------------------------------------
const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2(-2, -2);
const infoEl = document.getElementById('info');
let hovered = null;

addEventListener('pointermove', (e) => {
  pointer.set((e.clientX / innerWidth) * 2 - 1, -(e.clientY / innerHeight) * 2 + 1);
});

function row(k, v) { return `<tr><td>${k}</td><td>${v}</td></tr>`; }

function updateHover() {
  raycaster.setFromCamera(pointer, camera);
  const hit = raycaster.intersectObjects(pickables, false)[0]?.object ?? null;
  if (hit === hovered) return;
  if (hovered) hovered.material.emissive?.setHex(0x000000);
  hovered = hit;
  if (!hovered) { infoEl.style.display = 'none'; return; }
  hovered.material.emissive?.setHex(0x223355);

  const d = hovered.userData;
  let html = `<h2>${d.kind}: ${d.name ?? ''}</h2><table>`;
  if (d.kind === 'Pod') {
    html += row('namespace', d.namespace) + row('node', d.node ?? '-') +
      row('phase', d.phase) + row('ready', `${d.ready}/${d.total}`) +
      row('sidecar', d.hasSidecar ? 'istio-proxy ✓' : 'なし') +
      (d.app ? row('app', d.app) : '');
  } else if (d.kind === 'Node') {
    html += row('instance', d.instanceType) + row('allocatable cpu', d.cpu) + row('memory', d.memory);
  } else if (d.kind === 'LoadBalancer') {
    html += row('service', `${d.namespace}/${d.name}`) + row('external IP', d.externalIP);
  }
  infoEl.innerHTML = html + '</table>';
  infoEl.style.display = 'block';
}

// ----------------------------------------------------------------------
// ループ / リサイズ / 起動
// ----------------------------------------------------------------------
const clock = new THREE.Clock();
renderer.setAnimationLoop(() => {
  const dt = Math.min(clock.getDelta(), 0.1);
  controls.update();
  flows.forEach((f) => f.dots.forEach((d) => {
    d.t = (d.t + dt * 0.18) % 1;
    d.mesh.position.copy(f.curve.getPoint(d.t));
  }));
  updateHover();
  renderer.render(scene, camera);
  labelRenderer.render(scene, camera);
});

addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
  labelRenderer.setSize(innerWidth, innerHeight);
});

fetch('./data.json')
  .then((r) => { if (!r.ok) throw new Error(`data.json: ${r.status}`); return r.json(); })
  .then(buildScene)
  .catch((err) => {
    document.getElementById('meta').textContent =
      `data.json が読めません (${err.message})。./generate-data.sh を実行してください`;
  });
