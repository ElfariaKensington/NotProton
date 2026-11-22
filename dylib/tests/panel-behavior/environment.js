'use strict';
// Drive General-tab Launch Options + Compatibility-tab env integration:
// empty user-defined presets, Compatibility toggles writing to notproton.env,
// cross-tab sync, list/text modes, Disable/Enable, Clear/Undo, validation, and concurrency.
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

function hooks() {
  const state = [], cleanups = [];
  let at = 0;
  return {
    use: init => {
      const i = at++;
      if (!(i in state)) state[i] = init;
      return [state[i], v => { state[i] = typeof v === 'function' ? v(state[i]) : v; }];
    },
    effect: fn => {
      const i = at++;
      if (!(i in state)) { state[i] = true; const c = fn(); if (typeof c === 'function') cleanups.push(c); }
    },
    reset: () => { at = 0; },
    unmount: () => cleanups.splice(0).forEach(f => f()),
  };
}

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
  let stored = '', failLoad = false, failSave = false, waitSave;
  const h = hooks();
  const globals = {
    document: { documentElement: { lang: 'en' } },
    localStorage: {
      getItem: k => storage.has(k) ? storage.get(k) : null,
      setItem: (k, v) => storage.set(k, String(v)),
    },
    MSCXUseState: h.use,
    MSCXUseEffect: h.effect,
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

  // 1. Compatibility tab toggles/dropdowns/plugins write to notproton.env, NOT strLaunchOptions,
  //    and sync directly with the General-tab Launch Options env card.
  const FEATS = JSON.stringify([
    { k: 'NOTPROTON_TRUEHDR', l: 'TrueHDR', on: '1', off: '', dep: '', d: '' },
  ]).replace(/"(\w+)":/g, '$1:');
  const compat = panel(emit, 'statement', globals, { feats: FEATS });
  const renderCompat = (id = 480, opts = '') => {
    h.reset();
    return walk(compat.render({ details: details(opts, { unAppID: id }) }));
  };

  let cNodes = renderCompat(480, '%command% -param');
  await settle();
  cNodes = renderCompat(480, '%command% -param');

  cNodes.find(x => x.props && x.props.label === 'MSync').props.onChange(true);
  await settle();
  cNodes = renderCompat(480, '%command% -param');
  cNodes.find(x => x.props && x.props.label === 'DLSS').props.onChange(true);
  await settle();
  assert.match(stored, /D3DM_ENABLE_METALFX=1/, 'Automatic DLSS writes D3DM_ENABLE_METALFX to env');
  cNodes = renderCompat(480, '%command% -param');
  cNodes.find(x => x.props && x.props.label === 'TrueHDR').props.onChange(true);
  await settle();
  cNodes = renderCompat(480, '%command% -param');
  cNodes.find(x => x.type === 'Dropdown' && (x.props.rgOptions || []).some(o => o.data === 'dxmt'))
    .props.onChange({ data: 'dxmt' });
  await settle();
  assert.ok(!/D3DM_ENABLE_METALFX=/.test(stored), 'switching to dxmt clears D3DM_ENABLE_METALFX from env');
  cNodes = renderCompat(480, '%command% -param');
  cNodes.find(x => x.props && x.props.label === 'DLSS').props.onChange(true);
  await settle();

  assert.deepEqual(compat.written, [], 'Compatibility options never write to SetAppLaunchOptions');
  assert.match(stored, /WINEMSYNC=1/);
  assert.match(stored, /DXMT_ENABLE_NVEXT=1/);
  assert.match(stored, /NOTPROTON_TRUEHDR=1/);
  assert.match(stored, /CX_GRAPHICS_BACKEND=dxmt/);

  // Legacy env vars in strLaunchOptions are stripped when toggled in Compatibility tab.
  cNodes = renderCompat(480, 'WINEMSYNC=1 %command% -param');
  cNodes.find(x => x.props && x.props.label === 'MSync').props.onChange(false);
  await settle();
  assert.equal(compat.written.at(-1).opts, '%command% -param', 'legacy WINEMSYNC stripped from launch args');
  assert.ok(!/WINEMSYNC=/.test(stored));

  // Turn MSync back on for General tab inspection.
  cNodes = renderCompat(480, '%command% -param');
  cNodes.find(x => x.props && x.props.label === 'MSync').props.onChange(true);
  await settle();

  // 2. General tab Launch Options reads those exact env vars into the flat card & starts with empty presets.
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
  await settle();
  let rows = ui.envBody.findAll(el => el.className === 'NPLOEnvRow');
  const keysInUI = rows.map(r => r.find(el => el.className === 'NPLOEnvKey').value);
  assert.deepEqual(keysInUI, ['NOTPROTON_TRUEHDR', 'CX_GRAPHICS_BACKEND', 'DXMT_ENABLE_NVEXT', 'WINEMSYNC']);
  assert.equal(ui.argsInput.value, '%command% -param');

  // Presets start completely empty until defined by the user.
  assert.equal(ui.presetLabel.textContent, 'Preset: None');
  ui.presetBtn.onclick({ stopPropagation() {} });
  assert.equal(ui.popover.hidden, false);
  assert.equal(ui.presetList.children[0].textContent, 'No saved presets');
  assert.ok(!ui.presetList.find(el => el.textContent === 'Reset defaults'), 'no hardcoded default presets');

  // Save a user preset, verify it persists and matches, then delete it back to empty.
  ui.addPresetBtn.onclick({ stopPropagation() {} });
  ui.presetInput.value = 'My DXMT Setup';
  ui.presetSaveBtn.onclick({ stopPropagation() {} });
  assert.equal(ui.presetLabel.textContent, 'Preset: My DXMT Setup');
  assert.ok(storage.get('NotProtonLaunchPresets_v1').includes('My DXMT Setup'));

  // Typing launch arguments calls setValue without touching notproton.env, switches label to Custom.
  const prevEnvWrites = writes.length;
  ui.argsInput.value = '%command% -novid';
  ui.argsInput.oninput();
  assert.equal(launchWrites.at(-1).v, '%command% -novid');
  assert.equal(writes.length, prevEnvWrites, 'typing args does not write notproton.env');
  assert.equal(ui.presetLabel.textContent, 'Preset: Custom');

  // Applying user preset restores its args and env.
  ui.presetBtn.onclick({ stopPropagation() {} });
  ui.presetList.find(el => el.className && el.className.includes('NPLOPresetPick')).onclick({ stopPropagation() {} });
  await settle();
  assert.equal(ui.argsInput.value, '%command% -param');
  assert.equal(ui.presetLabel.textContent, 'Preset: My DXMT Setup');

  // Deleting the user preset leaves presets empty again.
  ui.presetBtn.onclick({ stopPropagation() {} });
  ui.presetList.find(el => el.className === 'NPLOPresetDel').onclick({ stopPropagation() {} });
  assert.equal(ui.presetList.children[0].textContent, 'No saved presets');
  assert.equal(ui.presetLabel.textContent, 'Preset: None');
  doc.dispatchClick(root);
  assert.equal(ui.popover.hidden, true);

  // Adding, editing, and removing a variable in list mode.
  const prevLaunchWrites = launchWrites.length;
  ui.addVarBtn.onclick({ stopPropagation() {} });
  rows = ui.envBody.findAll(el => el.className === 'NPLOEnvRow');
  const kNew = rows.at(-1).find(el => el.className === 'NPLOEnvKey');
  const vNew = rows.at(-1).find(el => el.className === 'NPLOEnvVal');
  assert.equal(doc.activeElement, kNew, 'adding a variable focuses its name input');
  kNew.value = 'UNICODE_VAR';
  kNew.oninput();
  vNew.value = 'Türkçe 日本語';
  vNew.oninput();
  vNew.onblur();
  await settle();
  assert.match(stored, /UNICODE_VAR=Türkçe 日本語/);
  assert.equal(launchWrites.length, prevLaunchWrites, 'editing env never calls SetAppLaunchOptions');

  // Invalid variable name is rejected before transport.
  const saveCountBeforeBad = writes.length;
  kNew.value = 'INVALID KEY';
  kNew.oninput();
  kNew.onblur();
  await settle();
  assert.equal(writes.length, saveCountBeforeBad, 'invalid key never reaches transport');
  assert.match(ui.statusMsg.textContent, /Not saved/);

  // Fix key back and test Edit as text -> Edit as list.
  kNew.value = 'LITERAL_CMD';
  kNew.oninput();
  vNew.value = '$(touch nope) "quoted"';
  vNew.oninput();
  vNew.onblur();
  await settle();
  assert.match(stored, /LITERAL_CMD=\$\(touch nope\) "quoted"/);

  ui.modeBtn.onclick();
  assert.equal(ui.textWrap.hidden, false);
  assert.equal(ui.envBody.hidden, true);
  assert.equal(ui.addVarBtn.hidden, true);
  assert.equal(ui.modeBtn.textContent, 'Edit as list');
  ui.textArea.value = '# keep note\nHELLO=two words=literal\nWINEMSYNC=1';
  ui.textArea.oninput();
  ui.textArea.onblur();
  await settle();
  assert.equal(stored, '# keep note\nHELLO=two words=literal\nWINEMSYNC=1');

  // Compatibility tab reads the updated env immediately.
  cNodes = renderCompat(480, '%command% -param');
  assert.equal(cNodes.find(x => x.props && x.props.label === 'MSync').props.checked, true);
  assert.equal(cNodes.find(x => x.props && x.props.label === 'TrueHDR').props.checked, false);

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
  cNodes = renderCompat(480, '%command% -param');
  assert.equal(cNodes.find(x => x.props && x.props.label === 'MSync').props.checked, false, 'disabled env reads off in Compatibility');

  // Reloading another app preserves disabled state from stored text.
  ui = mount(481, '');
  await settle();
  assert.equal(ui.bypassBtn.textContent, 'Enable');
  assert.match(ui.envBody.className, /bypassed/);

  ui.bypassBtn.onclick();
  await settle();
  assert.equal(ui.bypassBtn.textContent, 'Disable');
  assert.equal(stored, '# keep note\nHELLO=two words=literal\nWINEMSYNC=1');

  // Clear and Undo clear.
  ui.argsInput.value = '%command% -windowed';
  ui.argsInput.oninput();
  ui.clearBtn.onclick();
  await settle();
  assert.equal(ui.argsInput.value, '');
  assert.equal(stored, '');
  assert.equal(ui.undoBtn.hidden, false);
  ui.undoBtn.onclick();
  await settle();
  assert.equal(ui.argsInput.value, '%command% -windowed');
  assert.equal(stored, '# keep note\nHELLO=two words=literal\nWINEMSYNC=1');
  assert.equal(ui.undoBtn.hidden, true);

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

  // Load failure + Retry on a fresh appId.
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

  // Third-party tools (!ours) still fall back to strLaunchOptions.
  const foreign = panel(emit, 'statement', globals, {
    feats: JSON.stringify([{ k: 'NOTPROTON_HUD', l: 'Hud', on: '1', off: '', dep: '', d: '', rq: '/lib/libhud.dylib', ev: ['HUD=1'] }]).replace(/"(\w+)":/g, '$1:'),
    ourTools: [['notproton', '27.0']],
  });
  h.reset();
  const fNodes = walk(foreign.render({ details: details('', { unAppID: 483, strCompatToolName: 'crossover-25' }) }));
  fNodes.find(x => x.props && x.props.label === 'Hud').props.onChange(true);
  assert.equal(foreign.written[0].opts, 'env DYLD_INSERT_LIBRARIES=/lib/libhud.dylib HUD=1 %command%');

  h.unmount();
  console.log('==> unified env store, empty presets, compatibility sync, list/text modes, disable, clear/undo, retry and concurrency pass');
})().catch(e => { console.error(e); process.exitCode = 1; });
