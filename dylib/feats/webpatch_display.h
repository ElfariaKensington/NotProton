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
    "   hint=el('div','MSCXDisplayHint','Runs on the main display in a macOS fullscreen Space at the selected resolution. Your Mac’s display settings stay unchanged.')," \
    "   status=el('div','MSCXDisplayHint'),retry=el('button','MSCXBtn','Retry');" \
    "  select.setAttribute('aria-label','Fullscreen resolution');status.setAttribute('role','status');" \
    "  const choices=[['','Use game settings'],['1280x720','1280 × 720'],['1600x900','1600 × 900'],['1920x1080','1920 × 1080'],['2560x1440','2560 × 1440'],['3440x1440','3440 × 1440'],['3840x2160','3840 × 2160'],['custom','Custom…']];" \
    "  for(const [value,title] of choices){const option=el('option','',title);option.value=value;select.append(option)}" \
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
    "  select.onchange=()=>{if(select.value==='custom'&&!width.value){width.value=1920;height.value=1080}update();show('Apply to use this setting on the next launch.')};" \
    "  width.oninput=height.oninput=()=>{update();show('Apply to use this setting on the next launch.')};" \
    "  const load=()=>{loading=true;retry.hidden=true;update();show('Loading…');" \
    "   Promise.resolve().then(()=>globalThis.MSCXRoute('NotProton.GetDisplay#1',id)).then(text=>{" \
    "    if(!live())return;saved=text;const preset=choices.some(([v])=>v===text);select.value=preset?text:'custom';" \
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
    "  (0," RT ".jsx)('style',{children:'.MSCXDisplayControls{display:flex;flex-wrap:wrap;align-items:center;gap:8px}.MSCXDisplaySelect,.MSCXDisplayNumber{box-sizing:border-box;color:#dfe3e6;background:#222a35;border:1px solid #59616c;border-radius:3px;padding:8px;font:inherit;min-width:0}.MSCXDisplaySelect{flex:1 1 190px}.MSCXDisplayNumber{width:95px}.MSCXDisplaySize{display:flex;align-items:center;gap:6px}.MSCXDisplaySize[hidden]{display:none}.MSCXDisplayHint{margin-top:8px;font-size:12px;line-height:1.4;color:#a7adb4}.MSCXDisplayControls :focus-visible{outline:1px solid #66c0f4;outline-offset:-1px}'})," \
    "  (0," RT ".jsx)('div',{className:'MSCXDisplayEditor',ref:e=>e&&attach(e,t.unAppID)},'display-'+t.unAppID)" \
    " ]},'display');" \
    "})()"
#endif
