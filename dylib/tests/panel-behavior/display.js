'use strict';
const assert = require('node:assert/strict');
const { panel, walk, details, FORMS } = require('./harness');
const settle = () => new Promise(r => setImmediate(r));
class Element {
  constructor(tag) { this.tag = tag; this.children = []; this.value = ''; this.isConnected = true; }
  setAttribute(name, value) { this[name] = value; }
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this.children = children; }
  get firstChild() { return this.children[0]; }
}
(async () => {
 for (const form of Object.keys(FORMS)) {
  const writes = [], reads = [];
  let stored = '1920x1080', failLoad = false, failSave = false;
  const globals = { document: { documentElement: { lang: 'en' } },
   MSCXRoute: async (route,id) => { reads.push({route,id});if(failLoad)throw Error('offline');return route==='NotProton.GetDisplayModes#1'?JSON.stringify({current:[2056,1329],pixels:[4112,2658],modes:[[2056,1329],[2560,1600],[4112,2658]]}):stored },
   MSCXSpecifyRoute: async (route,id,text) => { writes.push({route,id,text});if(!failSave)stored=text;return {GetEResult:()=>failSave?2:1} }
  };
  const p = panel(process.argv[2], form, globals);
  function mount(id) {
   const nodes=walk(p.render({details:details('user args',{unAppID:id})}));
   assert.equal(nodes.filter(n=>n.type==='Section').at(-1).props.label,'Fullscreen resolution');
   const root=new Element('div');root.ownerDocument={createElement:tag=>new Element(tag)};
   const ref=nodes.find(n=>n.props.className==='MSCXDisplayEditor').props.ref;
   ref(root);
   const [row,hint,status,retry]=root.children;
   const [select,size,apply]=row.children;const [width,separator,height]=size.children;
   return {root,ref,select,size,width,height,apply,status,retry};
  }
  let e=mount(480);assert(e.select.disabled);await settle();
  assert.equal(e.select.value,'1920x1080');assert(e.apply.disabled);
  e.ref(e.root);await settle();assert.equal(reads.length,2);
  const options=e.select.children.flatMap(n=>n.tag==='optgroup'?n.children:[n]);
  assert(options.some(n=>n.value==='2056x1329'));assert(options.some(n=>n.value==='4112x2658'));
  assert.equal(options.filter(n=>n.value==='2560x1600').length,1,'system and common modes deduplicate');
  e.select.value='custom';e.select.onchange();e.width.value='2560';e.height.value='1440';e.width.oninput();
  assert.equal(e.size.hidden,false);e.apply.onclick();await settle();
  assert.equal(stored,'2560x1440');assert.equal(writes.at(-1).route,'NotProton.SetDisplay#1');
  assert.equal(writes.at(-1).id,480);assert.match(e.status.textContent,/Saved/);
  const count=writes.length;e.width.value='10';e.width.oninput();e.apply.onclick();await settle();
  assert.equal(writes.length,count);assert.match(e.status.textContent,/640/);
  e.select.value='1280x720';e.select.onchange();failSave=true;e.apply.onclick();await settle();
  assert.match(e.status.textContent,/Could not save/);assert.equal(stored,'2560x1440');
  failSave=false;e.apply.onclick();await settle();assert.equal(stored,'1280x720');
  e.select.value='';e.select.onchange();assert(e.size.hidden);e.apply.onclick();await settle();assert.equal(stored,'');
  e=mount(481);await settle();e.select.value='1920x1080';e.select.onchange();e.apply.onclick();await settle();
  assert.equal(writes.at(-1).id,481);
  failLoad=true;e=mount(482);await settle();assert(e.select.disabled);assert.equal(e.retry.hidden,false);
  failLoad=false;e.retry.onclick();await settle();assert.equal(e.select.disabled,false);
  assert.deepEqual(p.written,[],'resolution settings never alter Steam launch options');
  console.log(`==> display editor (${form}): presets, custom, reset, errors, appids and launch-options isolation pass`);
 }
})().catch(e=>{console.error(e);process.exitCode=1});
