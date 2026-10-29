'use strict';
// Drive the actual injected editor, including asynchronous transport and focus events.
const assert = require('node:assert/strict');
const { panel, walk, details, FORMS } = require('./harness');
const emit = process.argv[2];
const settle = () => new Promise(resolve => setImmediate(resolve));
class Element {
  constructor(tag) { this.tag = tag; this.children = []; this.value = ''; this.textContent = ''; this.isConnected = true; }
  setAttribute(name, value) { this[name] = value; }
  replaceChildren(...children) { this.children = children; }
  get firstChild() { return this.children[0]; }
}
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
(async () => {
  for (const form of Object.keys(FORMS)) {
    const reads = [], writes = [];
    let stored = '# saved\nFOO=bar\n', failLoad = false, failSave = false, waitSave;
    const globals = {
      document: { documentElement: { lang: 'en' } },
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
    const p = panel(emit, form, globals);
    const mount = id => {
      const nodes = walk(p.render({ details: details('user-game-args', { unAppID: id }) }));
      assert.equal(nodes.filter(x => x.type === 'Section').at(-1).props.label, 'Environment variables');
      const root = new Element('div');
      root.ownerDocument = { createElement: tag => new Element(tag) };
      const ref = nodes.find(x => x.props.className === 'MSCXEnvEditor').props.ref;
      ref(root);
      const [field, status, retry] = root.children;
      return { root, ref, field, status, retry };
    };
    let editor = mount(480);
    assert.equal(editor.field.disabled, true);
    await settle();
    assert.equal(editor.field.value, stored);
    assert.equal(editor.field.disabled, false);
    editor.ref(editor.root);
    await settle();
    assert.equal(reads.length, 1, 'rerender preserves the editor without refetching');
    const edit = text => { editor.field.value = text; editor.field.oninput(); editor.field.onblur(); };
    edit('HELLO=two words=literal\nEMPTY=\nUNICODE=日本語');
    await settle();
    assert.equal(stored, editor.field.value);
    assert.equal(writes.at(-1).route, 'NotProton.SetGameEnvironment#1');
    assert.equal(writes.at(-1).id, 480);
    assert.match(editor.status.textContent, /Saved/);
    const count = writes.length;
    edit('INVALID KEY=no');
    await settle();
    assert.equal(writes.length, count, 'invalid input never reaches the transport');
    assert.match(editor.status.textContent, /Not saved/);
    failSave = true;
    edit('RETRY=yes');
    await settle();
    assert.match(editor.status.textContent, /Could not save/);
    failSave = false;
    editor.field.onblur();
    await settle();
    assert.equal(stored, 'RETRY=yes');
    // Reverting while the previous save is pending must still write the revert.
    const waiting = deferred(); waitSave = waiting;
    edit('TEMP=pending'); await settle();
    edit('RETRY=yes');
    waiting.resolve(); await settle(); await settle();
    assert.equal(stored, 'RETRY=yes');
    edit(''); await settle();
    assert.equal(stored, '', 'clearing the editor persists an empty environment');
    editor.root.isConnected = false;
    stored = 'OTHER=game';
    editor = mount(481); await settle();
    assert.equal(editor.field.value, stored);
    edit('OTHER=updated'); await settle();
    assert.equal(writes.at(-1).id, 481, 'switching games routes writes to the new appid');
    failLoad = true;
    editor = mount(482); await settle();
    assert.equal(editor.field.disabled, true);
    assert.equal(editor.retry.hidden, false);
    failLoad = false;
    editor.retry.onclick(); await settle();
    assert.equal(editor.field.disabled, false);
    assert.equal(editor.retry.hidden, true);
    assert.deepEqual(p.written, [], 'editor never calls SetAppLaunchOptions');
    console.log(`==> environment editor (${form}): loading, saving, clearing, retry, ordering and launch-options isolation pass`);
  }
})().catch(e => { console.error(e); process.exitCode = 1; });
