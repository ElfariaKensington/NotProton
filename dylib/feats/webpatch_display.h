// The per-game resolution editor is kept outside the shared compatibility panel.
#ifndef NOTPROTON_WEBPATCH_DISPLAY_H
#define NOTPROTON_WEBPATCH_DISPLAY_H
#define NP_CX_DISPLAY_SECTION(RT, BARREL) \
    "(()=>{" \
    " const attach=(root,id)=>{" \
    "  if(root.npDisplayApp===id)return;" \
    "  root.npDisplayApp=id;" \
    "  const doc=root.ownerDocument,el=(tag,cls,text)=>{const n=doc.createElement(tag);if(cls)n.className=cls;if(text)n.textContent=text;return n};" \
    "  const row=el('div','MSCXDisplayControls'),select=el('select','MSCXDisplaySelect'),size=el('div','MSCXDisplaySize')," \
    "   width=el('input','MSCXDisplayNumber'),height=el('input','MSCXDisplayNumber'),apply=el('button','MSCXBtn')," \
    "   hint=el('div','MSCXDisplayHint','Sets the game’s virtual desktop resolution. Fullscreen follows the game’s display mode; windowed mode stays available. Your Mac’s display settings stay unchanged.')," \
    "   status=el('div','MSCXDisplayHint'),retry=el('button','MSCXBtn','Retry');" \
    "  select.setAttribute('aria-label','Fullscreen resolution');status.setAttribute('role','status');" \
    "  const common=[[1280,720],[1280,800],[1440,900],[1600,900],[1680,1050],[1920,1080],[1920,1200],[2560,1440],[2560,1600],[3440,1440],[3840,2160],[3840,2400]];" \
    "  const pending=el('option','','Loading resolutions…');pending.value='';select.append(pending);" \
    "  const choices=[];let displayDefault=[1920,1080];" \
    "  const populate=info=>{" \
    "   choices.length=0;select.replaceChildren();const seen=new Set;" \
    "   const add=(parent,value,label)=>{const option=el('option','',label);option.value=value;parent.append(option);choices.push([value,label])};" \
    "   add(select,'','Use game settings');" \
    "   const group=(label,rows)=>{const node=el('optgroup');node.label=label;" \
    "    for(const pair of rows){if(!Array.isArray(pair)||pair.length!==2)continue;const [w,h]=pair.map(Number);" \
    "     if(!Number.isInteger(w)||!Number.isInteger(h)||w<640||h<480||w>16384||h>16384)continue;" \
    "     const value=w+'x'+h;if(seen.has(value))continue;seen.add(value);" \
    "     const current=Array.isArray(info.current)&&info.current[0]===w&&info.current[1]===h;" \
    "     add(node,value,w+' × '+h+(current?' (Current display)':''));" \
    "    }if(node.children.length)select.append(node);" \
    "   };" \
    "   group('Display resolutions',Array.isArray(info.modes)?info.modes:[]);group('Common game resolutions',common);" \
    "   if(Array.isArray(info.current)&&info.current[0]>=640&&info.current[1]>=480)displayDefault=info.current;" \
    "   add(select,'custom','Custom…');" \
    "  };" \
    "  for(const [input,name,min] of [[width,'Width',640],[height,'Height',480]]){" \
    "   input.type='number';input.min=min;input.max=16384;input.step=1;input.setAttribute('aria-label',name);" \
    "  }" \
    "  size.append(width,el('span','','×'),height);size.hidden=true;retry.hidden=true;" \
    "  row.append(select,size,apply);root.replaceChildren(row,hint,status,retry);" \
    "  const live=()=>root.isConnected&&root.npDisplayApp===id&&root.firstChild===row;" \
    "  let saved='',loading=true,saving=false;" \
    "  const value=()=>select.value==='custom'?width.value+'x'+height.value:select.value;" \
    "  const update=()=>{size.hidden=select.value!=='custom';apply.textContent=saving?'Saving…':'Apply';" \
    "   select.disabled=loading||saving;width.disabled=loading||saving;height.disabled=loading||saving;" \
    "   apply.disabled=loading||saving||value()===saved};" \
    "  const show=text=>{if(live())status.textContent=text};" \
    "  select.onchange=()=>{if(select.value==='custom'&&!width.value){[width.value,height.value]=displayDefault}update();show('Apply to use this setting on the next launch.')};" \
    "  width.oninput=height.oninput=()=>{update();show('Apply to use this setting on the next launch.')};" \
    "  const load=()=>{loading=true;retry.hidden=true;update();show('Loading…');" \
    "   Promise.resolve().then(()=>Promise.all([globalThis.MSCXRoute('NotProton.GetDisplay#1',id),globalThis.MSCXRoute('NotProton.GetDisplayModes#1',id)])).then(([text,raw])=>{" \
    "    if(!live())return;populate(JSON.parse(raw));saved=text;const preset=choices.some(([v])=>v===text);select.value=preset?text:'custom';" \
    "    if(text){[width.value,height.value]=text.split('x')}loading=false;update();show('Applies when you next launch the game.');" \
    "   }).catch(()=>{show('Could not load the display settings.');if(live())retry.hidden=false});" \
    "  };" \
    "  apply.onclick=()=>{" \
    "   const text=value();if(loading||saving)return;" \
    "   if(text&&!/^[0-9]+x[0-9]+$/.test(text)){show('Enter a whole-number width and height.');return}" \
    "   const [w,h]=text.split('x').map(Number);" \
    "   if(text&&(w<640||h<480||w>16384||h>16384)){show('Use a resolution from 640 × 480 up to 16384 × 16384.');return}" \
    "   saving=true;update();show('Saving…');" \
    "   Promise.resolve().then(()=>globalThis.MSCXSpecifyRoute('NotProton.SetDisplay#1',id,text)).then(answer=>{" \
    "    if(answer.GetEResult()!==1)throw Error('save');saved=text;show('Saved. Restart the game to apply.');" \
    "   }).catch(()=>show('Could not save. Please try again.')).finally(()=>{saving=false;if(live())update()});" \
    "  };" \
    "  retry.onclick=load;load();" \
    " };" \
    " return (0," RT ".jsx)(" BARREL ".XY,{label:'Fullscreen resolution',children:[" \
    "  (0," RT ".jsx)('style',{children:'.MSCXDisplayControls{display:flex;flex-wrap:wrap;align-items:center;gap:8px}.MSCXDisplaySelect,.MSCXDisplayNumber{box-sizing:border-box;color:#dfe3e6;background:#222a35;border:1px solid #59616c;border-radius:3px;padding:8px;font:inherit;min-width:0}.MSCXDisplayControls :is(.MSCXDisplaySelect,.MSCXDisplayNumber,.MSCXBtn){box-sizing:border-box;height:2.5em;min-height:36px;font:inherit;line-height:1.25;margin:0}.MSCXDisplayControls>.MSCXBtn{display:inline-flex;align-items:center;justify-content:center;padding:0 14px}.MSCXDisplaySelect{flex:1 1 190px}.MSCXDisplayNumber{width:95px}.MSCXDisplaySize{display:flex;align-items:center;gap:6px}.MSCXDisplaySize[hidden]{display:none}.MSCXDisplayHint{margin-top:8px;font-size:12px;line-height:1.4;color:#a7adb4}.MSCXDisplayControls :focus-visible{outline:1px solid #66c0f4;outline-offset:-1px}'})," \
    "  (0," RT ".jsx)('div',{className:'MSCXDisplayEditor',ref:e=>e&&attach(e,t.unAppID)},'display-'+t.unAppID)" \
    " ]},'display');" \
    "})()"
#endif
