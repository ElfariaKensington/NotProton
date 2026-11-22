'use strict';
// Drive the General-tab Launch Options & Environment Variables editor, including
// presets, list/text modes, Disable/Enable, Clear/Undo, validation, and async saves.
const assert = require('node:assert/strict');
const { panel, launchOptions, walk, details, FORMS } = require('./harness');
const emit = process.argv[2];
const settle = () => new Promise(resolve => setImmediate(resolve));

class Element {
  constructor(tag, doc) {
    this.tag = tag;
    this.ownerDocument = doc || null;
    this.children = [];
    this.parentNode = null;
    this.className = '';
    this.value = '';
    this.textContent = '';
    this.hidden = false;
    this.disabled = false;
    this.isConnected = true;
    this.style = {};
    this.attrs = {};
  }
  setAttribute(name, value) { this.attrs[name] = value; }
  append(...nodes) {
    for (const n of nodes) {
      if (n && typeof n === 'object') { n.parentNode = this; this.children.push(n); }
    }
  }
  replaceChildren(...nodes) {
    this.children = [];
    this.append(...nodes);
  }
  get firstChild() { return this.children[0]; }
  focus() { if (this.ownerDocument) this.ownerDocument.activeElement = this; }
  contains(target) {
    if (target === this) return true;
    return this.children.some(c => c.contains(target));
  }
  find(pred) {
    if (pred(this)) return this;
    for (const c of this.children) {
      const hit = c.find(pred);
      if (hit) return hit;
    }
    return null;
  }
  findAll(pred, out = []) {
    if (pred(this)) out.push(this);
    for (const c of this.children) c.findAll(pred, out);
    return out;
  }
}

class Doc {
  constructor() {
    this.listeners = new Map();
    this.activeElement = null;
  }
  createElement(tag) { return new Element(tag, this); }
  addEventListener(ev, fn) {
    if (!this.listeners.has(ev)) this.listeners.set(ev, new Set());
    this.listeners.get(ev).add(fn);
  }
  removeEventListener(ev, fn) {
    this.listeners.get(ev)?.delete(fn);
  }
  dispatchClick(target) {
    for (const fn of [...(this.listeners.get('click') || [])]) {
      fn({ target, stopPropagation() {} });
    }
  }
}

const deferred = () => {
  let resolve;
  const promise = new Promise(r => { resolve = r; });
  return { promise, resolve };
};

(async () => {
  // Compatibility tab no longer appends the old plain Environment variables section.
  for (const form of Object.keys(FORMS)) {
    const p = panel(emit, form);
    const sections = walk(p.render({ details: details('') }))
      .filter(x => x.type === 'Section').map(x => x.props.label);
    assert.ok(!sections.includes('Environment variables'),
              `Compatibility panel (${form}) does not duplicate Environment variables`);
  }

  const reads = [], writes = [], launchWrites = [];
  const storage = new Map();
  let stored = 'DXMT_ENABLE_NVEXT=1\nCX_GRAPHICS_BACKEND=dxmt\n', failLoad = false, failSave = false, waitSave;
  const globals = {
    document: { documentElement: { lang: 'en' } },
    localStorage: {
      getItem: k => storage.has(k) ? storage.get(k) : null,
      setItem: (k, v) => storage.set(k, String(v)),
    },
    MSCXRoute: async (route, id) => {
      reads.push({ route, id });
      if (failLoad) throw Error('offline');
      return stored;
    },
    MSCXSpecifyRoute: async (route, id, text) => {
      writes.push({ route, id, text });
      if (waitSave) { const wait = waitSave; waitSave = null; await wait.promise; }
      if (failSave) return { GetEResult: () => 2 };
      stored = text;
      return { GetEResult: () => 1 };
    },
  };

  const LaunchOpts = launchOptions(emit, globals);
  const doc = new Doc();
  const root = new Element('div', doc);

  const mount = (id, value = '', extra = null) => {
    const props = {
      appId: id,
      value,
      title: 'Launch Options',
      extra,
      setValue: v => launchWrites.push({ id, v }),
    };
    const tree = walk(LaunchOpts(props));
    const host = tree.find(x => x.props && x.props.className === 'NPLOHost');
    assert.ok(host, 'renders NPLOHost');
    host.props.ref(root);
    return {
      props,
      argsInput: root.find(el => el.className === 'NPLOArgsInput'),
      presetBtn: root.find(el => el.className === 'NPLOPresetBtn'),
      presetLabel: root.find(el => el.className === 'NPLOPresetBtn').firstChild,
      popover: root.find(el => el.className === 'NPLOPopover'),
      presetList: root.find(el => el.className === 'NPLOPresetList'),
      addPresetBtn: root.find(el => el.className === 'NPLOPresetAddBtn'),
      presetForm: root.find(el => el.className === 'NPLOPresetForm'),
      presetInput: root.find(el => el.className === 'NPLOPresetInput'),
      presetSaveBtn: root.find(el => el.className === 'NPLOPresetSaveBtn'),
      envBody: root.find(el => el.className && el.className.startsWith('NPLOEnvBody')),
      textWrap: root.find(el => el.className && el.className.startsWith('NPLOEnvTextWrap')),
      textArea: root.find(el => el.className === 'NPLOEnvText'),
      statusRow: root.find(el => el.className === 'NPLOStatus'),
      statusMsg: root.find(el => el.className === 'NPLOStatus').firstChild,
      retryBtn: root.find(el => el.parentNode && el.parentNode.className === 'NPLOStatus' && el.textContent === 'Retry'),
      addVarBtn: root.find(el => el.textContent === '+ Add variable'),
      modeBtn: root.find(el => el.className === 'NPLOLink' && /^Edit as /.test(el.textContent)),
      bypassBtn: root.find(el => el.className === 'NPLOLink' && (el.textContent === 'Disable' || el.textContent === 'Enable')),
      undoBtn: root.find(el => el.textContent === 'Undo clear'),
      clearBtn: root.find(el => el.textContent === 'Clear'),
    };
  };

  let ui = mount(480, '%command% -param');
  assert.equal(ui.textArea.disabled, true);
  assert.equal(ui.argsInput.value, '%command% -param');
  await settle();
  assert.equal(ui.textArea.disabled, false);
  assert.equal(ui.envBody.findAll(el => el.className === 'NPLOEnvRow').length, 2);

  // Re-render for the same appId preserves without refetching and syncs external args.
  mount(480, '%command% -param');
  await settle();
  assert.equal(reads.length, 1, 'rerender preserves without refetching');
  mount(480, '%command% -external');
  assert.equal(ui.argsInput.value, '%command% -external', 'external strLaunchOptions update applies');

  // Typing launch arguments calls setValue without touching notproton.env.
  const prevEnvWrites = writes.length;
  ui.argsInput.value = '%command% -novid';
  ui.argsInput.oninput();
  assert.equal(launchWrites.at(-1).v, '%command% -novid');
  assert.equal(writes.length, prevEnvWrites, 'typing args does not write notproton.env');
  assert.equal(ui.presetLabel.textContent, 'Preset: Custom');

  // Adding, editing, and removing a variable in list mode.
  const prevLaunchWrites = launchWrites.length;
  ui.addVarBtn.onclick({ stopPropagation() {} });
  let rows = ui.envBody.findAll(el => el.className === 'NPLOEnvRow');
  assert.equal(rows.length, 3);
  const k3 = rows[2].find(el => el.className === 'NPLOEnvKey');
  const v3 = rows[2].find(el => el.className === 'NPLOEnvVal');
  assert.equal(doc.activeElement, k3, 'adding a variable focuses its name input');
  k3.value = 'UNICODE_VAR';
  k3.oninput();
  v3.value = 'Türkçe 日本語';
  v3.oninput();
  v3.onblur();
  await settle();
  assert.match(stored, /UNICODE_VAR=Türkçe 日本語/);
  assert.equal(launchWrites.length, prevLaunchWrites, 'editing env never calls SetAppLaunchOptions');

  // Invalid variable name is rejected before transport.
  const saveCountBeforeBad = writes.length;
  k3.value = 'INVALID KEY';
  k3.oninput();
  k3.onblur();
  await settle();
  assert.equal(writes.length, saveCountBeforeBad, 'invalid key never reaches transport');
  assert.match(ui.statusMsg.textContent, /Not saved/);

  // Fix key back and test Edit as text -> Edit as list.
  k3.value = 'LITERAL_CMD';
  k3.oninput();
  v3.value = '$(touch nope) "quoted"';
  v3.oninput();
  v3.onblur();
  await settle();
  assert.match(stored, /LITERAL_CMD=\$\(touch nope\) "quoted"/);

  ui.modeBtn.onclick();
  assert.equal(ui.textWrap.hidden, false);
  assert.equal(ui.envBody.hidden, true);
  assert.equal(ui.addVarBtn.hidden, true);
  assert.equal(ui.modeBtn.textContent, 'Edit as list');
  ui.textArea.value = '# keep note\nHELLO=two words=literal\nEMPTY=';
  ui.textArea.oninput();
  ui.textArea.onblur();
  await settle();
  assert.equal(stored, '# keep note\nHELLO=two words=literal\nEMPTY=');

  ui.modeBtn.onclick();
  await settle();
  assert.equal(ui.envBody.hidden, false);
  assert.equal(ui.modeBtn.textContent, 'Edit as text');
  assert.equal(ui.envBody.findAll(el => el.className === 'NPLOEnvRow').length, 2);

  // Disable / Enable persists # notproton-disabled in notproton.env and sets bypassed class.
  ui.bypassBtn.onclick();
  await settle();
  assert.equal(ui.bypassBtn.textContent, 'Enable');
  assert.match(ui.envBody.className, /bypassed/);
  assert.ok(stored.startsWith('# notproton-disabled\n'), 'disabled state persisted via comment header');

  // Reloading preserves disabled state.
  ui = mount(481, '');
  await settle();
  assert.equal(ui.bypassBtn.textContent, 'Enable');
  assert.match(ui.envBody.className, /bypassed/);
  assert.equal(ui.envBody.findAll(el => el.className === 'NPLOEnvRow').length, 2);

  ui.bypassBtn.onclick();
  await settle();
  assert.equal(ui.bypassBtn.textContent, 'Disable');
  assert.equal(stored, '# keep note\nHELLO=two words=literal\nEMPTY=');

  // Presets: switch to DXMT Metal, save custom preset, delete preset, reset defaults.
  ui.presetBtn.onclick({ stopPropagation() {} });
  assert.equal(ui.popover.hidden, false);
  const dxmtPick = ui.presetList.find(el => el.className && el.className.includes('NPLOPresetPick') && el.textContent === 'DXMT Metal');
  dxmtPick.onclick({ stopPropagation() {} });
  await settle();
  assert.equal(ui.popover.hidden, true);
  assert.equal(ui.presetLabel.textContent, 'Preset: DXMT Metal');
  assert.equal(stored, 'DXMT_ENABLE_NVEXT=1\nCX_GRAPHICS_BACKEND=dxmt');

  // Save custom preset.
  ui.argsInput.value = '%command% -custom';
  ui.argsInput.oninput();
  ui.presetBtn.onclick({ stopPropagation() {} });
  ui.addPresetBtn.onclick({ stopPropagation() {} });
  assert.equal(ui.presetForm.hidden, false);
  ui.presetInput.value = 'My Preset';
  ui.presetSaveBtn.onclick({ stopPropagation() {} });
  assert.equal(ui.presetLabel.textContent, 'Preset: My Preset');
  assert.ok(storage.get('NotProtonLaunchPresets_v1').includes('My Preset'));

  // Clear and Undo clear.
  ui.clearBtn.onclick();
  await settle();
  assert.equal(ui.argsInput.value, '');
  assert.equal(stored, '');
  assert.equal(ui.undoBtn.hidden, false);
  ui.undoBtn.onclick();
  await settle();
  assert.equal(ui.argsInput.value, '%command% -custom');
  assert.equal(stored, 'DXMT_ENABLE_NVEXT=1\nCX_GRAPHICS_BACKEND=dxmt');
  assert.equal(ui.undoBtn.hidden, true);

  // Delete all presets -> shows Reset defaults -> clicking restores DXMT Metal.
  ui.presetBtn.onclick({ stopPropagation() {} });
  while (true) {
    const del = ui.presetList.find(el => el.className === 'NPLOPresetDel');
    if (!del) break;
    del.onclick({ stopPropagation() {} });
  }
  const resetBtn = ui.presetList.find(el => el.textContent === 'Reset defaults');
  assert.ok(resetBtn, 'deleting all presets shows Reset defaults');
  resetBtn.onclick({ stopPropagation() {} });
  assert.ok(ui.presetList.find(el => el.textContent === 'DXMT Metal'), 'Reset defaults restores presets');
  doc.dispatchClick(root);
  assert.equal(ui.popover.hidden, true, 'clicking outside closes preset popover');

  // Save failure + Retry and concurrent revert ordering.
  failSave = true;
  ui.modeBtn.onclick();
  ui.textArea.value = 'RETRY=yes';
  ui.textArea.oninput();
  ui.textArea.onblur();
  await settle();
  assert.match(ui.statusMsg.textContent, /Could not save/);
  assert.equal(ui.retryBtn.hidden, false);
  failSave = false;
  ui.retryBtn.onclick();
  await settle();
  assert.equal(stored, 'RETRY=yes');

  const waiting = deferred();
  waitSave = waiting;
  ui.textArea.value = 'TEMP=pending';
  ui.textArea.oninput();
  ui.textArea.onblur();
  await settle();
  ui.textArea.value = 'RETRY=yes';
  ui.textArea.oninput();
  ui.textArea.onblur();
  waiting.resolve();
  await settle();
  await settle();
  assert.equal(stored, 'RETRY=yes', 'reverting while a save is pending still writes the revert');

  // Load failure + Retry.
  failLoad = true;
  ui = mount(482, '');
  await settle();
  assert.equal(ui.textArea.disabled, true);
  assert.equal(ui.retryBtn.hidden, false);
  failLoad = false;
  ui.retryBtn.onclick();
  await settle();
  assert.equal(ui.textArea.disabled, false);
  assert.equal(ui.retryBtn.hidden, true);

  console.log('==> launch options & environment editor: presets, list/text modes, disable, clear/undo, validation, retry and concurrency pass');
})().catch(e => { console.error(e); process.exitCode = 1; });
