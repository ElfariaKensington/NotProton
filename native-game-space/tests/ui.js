const assert = require('node:assert/strict');
const vm = require('node:vm');
const {execFileSync} = require('node:child_process');

class Element {
    constructor(tag) {
        this.tag = tag;
        this.children = [];
        this.style = {};
        this.value = '';
        this.validity = {get valid() {
            const n = Number(this.element.value);
            return Number.isInteger(n) && n >= Number(this.element.min) && n <= Number(this.element.max);
        }, element: this};
    }
    append(...nodes) { this.children.push(...nodes); }
    replaceChildren() { this.children = []; }
    setAttribute() {}
    focus() { this.focused = true; }
    click() { this.onclick(); }
    querySelector(tag) {
        for (const child of this.children) {
            if (child.tag === tag) return child;
            const found = child.querySelector(tag);
            if (found) return found;
        }
    }
}

const source = execFileSync(process.argv[2], {encoding: 'utf8'});
let saved = {}, appid = 42;
const writes = [];
const context = vm.createContext({
    document: {createElement: tag => new Element(tag)},
    R: {jsx: (tag, props) => props},
    g: key => saved[key] || '',
    t: {get unAppID() { return appid; }},
    L: {s: changes => { writes.push(changes); for (const [k, v] of changes) saved[k] = v; }},
});
const render = () => vm.runInContext(source, context).ref(root);
const root = new Element('div');
render();
let select = root.querySelector('select');
const presets = select.children.map(option => option.value).filter(value => value.includes('x'));
assert(presets.includes('320x200') && presets.includes('3840x2160'));
assert(presets.every(value => {
  const [width, height] = value.split('x').map(Number);
  return width <= 3840 && height <= 2160;
}));;
const custom = root.children[0].children[1];
let [width, , height, apply] = custom.children;
assert(width.disabled && height.disabled && apply.disabled);
select.value = 'custom'; select.onchange();
assert(!width.disabled && !height.disabled);
width.value = '2560'; height.value = '1440'; width.oninput(); apply.click();
assert.equal(saved.NOTPROTON_NATIVE_SIZE, '2560x1440');
assert.equal(saved.NOTPROTON_NATIVE_SIZE_MODE, 'custom');
render();
select = root.querySelector('select');
assert.equal(select.value, 'custom');
// Refs are called again on unrelated rerenders: saving must use the current callback.
render();
select.value = '3840x2160'; select.onchange();
assert.equal(saved.NOTPROTON_NATIVE_SIZE, '3840x2160');
assert.equal(saved.NOTPROTON_NATIVE_SIZE_MODE, '');
render();
select = root.querySelector('select');
select.value = ''; select.onchange();
assert.equal(saved.NOTPROTON_NATIVE_SIZE, '');
render();
select = root.querySelector('select');
select.value = 'custom'; select.onchange();
[width, , height, apply] = root.children[0].children[1].children;
width.value = '0'; width.oninput(); assert(apply.disabled);
width.value = '16385'; width.oninput(); assert(apply.disabled);
width.value = '1920.5'; width.oninput(); assert(apply.disabled);
width.value = '1920'; height.value = '1080'; width.oninput(); assert(!apply.disabled);
appid = 43; render();
assert.equal(root.querySelector('select').value, '');
console.log('native game Space UI: presets, custom, validation, rerenders, per-game reset passed');
