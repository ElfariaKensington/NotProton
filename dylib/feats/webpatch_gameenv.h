// General-tab Launch Options with presets and prefix-local environment variables.
#ifndef NOTPROTON_WEBPATCH_GAMEENV_H
#define NOTPROTON_WEBPATCH_GAMEENV_H

#define NP_LO_CSS \
    ".NPLOSection{margin-bottom:14px}" \
    ".NPLOHeader{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:8px}" \
    ".NPLOTitle{color:#fff;font-size:14.5px;font-weight:600;line-height:1.3;margin:0}" \
    ".NPLOPresetWrap{position:relative;flex-shrink:0}" \
    ".NPLOPresetBtn{background:#323741;color:#e3e6ea;font-size:12.5px;font-weight:400;line-height:1.3;border:none;border-radius:3px;padding:4px 10px 4px 12px;display:inline-flex;align-items:center;gap:8px;cursor:pointer;font-family:inherit;transition:background-color .15s ease}" \
    ".NPLOPresetBtn:hover{background:#3a404c}" \
    ".NPLOPresetChevron{width:14px;height:14px;color:#1a9fff;flex-shrink:0}" \
    ".NPLOPopover{position:absolute;right:0;top:calc(100% + 6px);width:260px;background:#252830;border:1px solid #3d4450;border-radius:4px;box-shadow:0 14px 32px rgba(0,0,0,.75);z-index:999;overflow:hidden}" \
    ".NPLOPopover[hidden]{display:none}" \
    ".NPLOPresetList{padding:4px 0;max-height:210px;overflow-y:auto}" \
    ".NPLOPresetItem{display:flex;align-items:center;justify-content:space-between;padding:6px 10px;border-bottom:1px solid rgba(45,49,59,.6);transition:background-color .15s ease}" \
    ".NPLOPresetItem:last-child{border-bottom:none}" \
    ".NPLOPresetItem:hover{background:#323741}" \
    ".NPLOPresetPick{flex:1;min-width:0;text-align:left;font-size:12.5px;color:#c9cfd8;background:none;border:none;padding:0 8px 0 0;cursor:pointer;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-family:inherit}" \
    ".NPLOPresetPick.active{color:#fff;font-weight:500}" \
    ".NPLOPresetDel{background:none;border:none;color:#67707b;padding:4px;border-radius:3px;cursor:pointer;display:inline-flex;align-items:center;flex-shrink:0;transition:color .15s ease}" \
    ".NPLOPresetDel:hover{color:#f26d6d}" \
    ".NPLOPresetEmpty{padding:10px 12px;text-align:center;font-size:12px;color:#7a828f}" \
    ".NPLOPopoverFoot{border-top:1px solid #323741;background:#20232a;padding:6px}" \
    ".NPLOPresetAddBtn{width:100%;text-align:left;padding:6px 10px;border-radius:3px;font-size:12.5px;color:#1a9fff;font-weight:500;background:none;border:none;cursor:pointer;display:flex;align-items:center;gap:6px;font-family:inherit;transition:background-color .15s ease,color .15s ease}" \
    ".NPLOPresetAddBtn:hover{background:rgba(50,55,65,.8);color:#47b2ff}" \
    ".NPLOPresetAddBtn[hidden]{display:none}" \
    ".NPLOPresetForm{display:flex;align-items:center;gap:6px}" \
    ".NPLOPresetForm[hidden]{display:none}" \
    ".NPLOPresetInput{flex:1;min-width:0;background:#171a21;border:1px solid #323741;border-radius:3px;padding:4px 8px;font-size:12px;color:#fff;outline:none;font-family:inherit}" \
    ".NPLOPresetInput:focus{border-color:#1a9fff}" \
    ".NPLOPresetSaveBtn{background:#1a9fff;color:#fff;font-size:11.5px;font-weight:500;padding:4px 10px;border-radius:3px;border:none;cursor:pointer;flex-shrink:0;font-family:inherit;transition:background-color .15s ease}" \
    ".NPLOPresetSaveBtn:hover{background:#33adff}" \
    ".NPLOArgsBox{background:#23262e;border-radius:4px;border:1px solid transparent;box-shadow:inset 0 1px 2px rgba(0,0,0,.38);padding:8px 14px;margin-bottom:10px;transition:border-color .15s ease}" \
    ".NPLOArgsBox:focus-within{border-color:rgba(26,159,255,.6)}" \
    ".NPLOArgsInput{box-sizing:border-box;width:100%;background:transparent;border:none;outline:none;font-size:13px;color:#e3e6ea;resize:none;overflow:hidden;line-height:20px;display:block;overflow-wrap:anywhere;padding:0;margin:0;font-family:inherit;user-select:text;-webkit-user-select:text}" \
    ".NPLOArgsInput::placeholder{color:#67707b}" \
    ".NPLOCard{background:#23262e;border-radius:4px;overflow:hidden}" \
    ".NPLOEnvBody{transition:opacity .15s ease}" \
    ".NPLOEnvBody.bypassed{opacity:.4}" \
    ".NPLOEnvBody[hidden]{display:none}" \
    ".NPLOEnvRow{padding:10px 16px;display:flex;align-items:flex-start;justify-content:space-between;gap:12px;border-bottom:1px solid #2c303a}" \
    ".NPLOEnvRow:last-child{border-bottom:none}" \
    ".NPLOEnvFields{flex:1;min-width:0}" \
    ".NPLOEnvKey{box-sizing:border-box;width:100%;background:transparent;border:none;outline:none;font-size:12px;font-weight:600;letter-spacing:.01em;color:#9ba1a9;padding:0;margin:0 0 2px;font-family:inherit;user-select:text;-webkit-user-select:text}" \
    ".NPLOEnvKey::placeholder{color:#5e6673}" \
    ".NPLOEnvVal{box-sizing:border-box;width:100%;background:transparent;border:none;outline:none;font-size:13px;color:#e3e6ea;resize:none;overflow:hidden;line-height:1.4;display:block;overflow-wrap:anywhere;padding:0;margin:0;font-family:inherit;user-select:text;-webkit-user-select:text}" \
    ".NPLOEnvVal::placeholder{color:#5e6673}" \
    ".NPLOEnvDel{background:none;border:none;color:#67707b;font-size:16px;line-height:1;padding:2px 4px;margin-top:2px;cursor:pointer;flex-shrink:0;transition:color .15s ease}" \
    ".NPLOEnvDel:hover{color:#e3e6ea}" \
    ".NPLOEnvEmpty{padding:12px 16px;font-size:12.5px;color:#67707b}" \
    ".NPLOEnvTextWrap{padding:12px 16px;transition:opacity .15s ease}" \
    ".NPLOEnvTextWrap.bypassed{opacity:.4}" \
    ".NPLOEnvTextWrap[hidden]{display:none}" \
    ".NPLOEnvText{box-sizing:border-box;width:100%;min-height:72px;background:transparent;border:none;outline:none;font-size:13px;color:#e3e6ea;resize:none;overflow:hidden;line-height:1.55;display:block;overflow-wrap:anywhere;padding:0;margin:0;font-family:inherit;user-select:text;-webkit-user-select:text}" \
    ".NPLOEnvText::placeholder{color:#5e6673}" \
    ".NPLOStatus{padding:6px 16px 8px;border-top:1px solid #2c303a;font-size:12px;color:#9ba1a9;display:flex;align-items:center;justify-content:space-between;gap:8px}" \
    ".NPLOStatus.error{color:#f26d6d}" \
    ".NPLOStatus[hidden]{display:none}" \
    ".NPLOFoot{padding:10px 16px;border-top:1px solid #2c303a;display:flex;align-items:center;justify-content:space-between;gap:12px}" \
    ".NPLOFootGroup{display:flex;align-items:center;gap:16px}" \
    ".NPLOLink{background:none;border:none;padding:0;font-size:12.5px;font-weight:500;color:#1a9fff;cursor:pointer;font-family:inherit;transition:color .15s ease,opacity .15s ease}" \
    ".NPLOLink:hover:not(:disabled){color:#47b2ff}" \
    ".NPLOLink:disabled{opacity:.35;pointer-events:none;cursor:default}" \
    ".NPLOLink[hidden]{display:none}"

#define NP_CX_LAUNCH_OPTIONS(RT, BARREL) \
    "((react,ui)=>{" \
    " const STORE_KEY='NotProtonLaunchPresets_v1';" \
    " const DISABLE_HDR='# notproton-disabled';" \
    " const DEFAULTS=()=>({" \
    "  dxmt:{label:'DXMT Metal',args:'',vars:[{key:'DXMT_ENABLE_NVEXT',val:'1'},{key:'CX_GRAPHICS_BACKEND',val:'dxmt'}]}," \
    "  debug:{label:'Windowed Debug',args:'%command% -windowed -w 1280 -h 720 -console',vars:[{key:'DXMT_HUD',val:'fps,devinfo,memory'},{key:'MTL_HUD_ENABLED',val:'1'}]}," \
    "  vanilla:{label:'Vanilla (None)',args:'',vars:[]}" \
    " });" \
    " const clone=x=>JSON.parse(JSON.stringify(x));" \
    " const loadPresets=()=>{" \
    "  try{" \
    "   const raw=globalThis.localStorage?.getItem(STORE_KEY);" \
    "   if(!raw)return DEFAULTS();" \
    "   const parsed=JSON.parse(raw);" \
    "   if(!parsed||typeof parsed!=='object'||Array.isArray(parsed))return DEFAULTS();" \
    "   const out={};" \
    "   for(const k of Object.keys(parsed)){" \
    "    const p=parsed[k];" \
    "    if(!p||typeof p!=='object'||typeof p.label!=='string'||!Array.isArray(p.vars))continue;" \
    "    out[k]={label:p.label,args:typeof p.args==='string'?p.args:'',vars:p.vars.filter(v=>v&&typeof v.key==='string').map(v=>({key:v.key,val:typeof v.val==='string'?v.val:''}))};" \
    "   }" \
    "   return out;" \
    "  }catch(_){return DEFAULTS()}" \
    " };" \
    " const savePresets=p=>{try{globalThis.localStorage?.setItem(STORE_KEY,JSON.stringify(p))}catch(_){}};" \
    " const keyOk=k=>/^[A-Za-z_][A-Za-z0-9_]*$/.test(k);" \
    " const parseText=(raw)=>{" \
    "  let lines=String(raw||'').split(/\\r?\\n/),disabled=false;" \
    "  if(lines.length&&lines[0].trim()===DISABLE_HDR){" \
    "   disabled=true;" \
    "   lines=lines.slice(1).map(l=>l.startsWith('# ')?l.slice(2):l.startsWith('#')?l.slice(1):l);" \
    "  }" \
    "  const vars=[],comments=[];" \
    "  for(const l of lines){" \
    "   const t=l.trim();" \
    "   if(!t)continue;" \
    "   if(t.startsWith('#')){comments.push(l);continue}" \
    "   const eq=l.indexOf('=');" \
    "   if(eq===-1)vars.push({key:t,val:''});" \
    "   else vars.push({key:l.slice(0,eq).trim(),val:l.slice(eq+1)});" \
    "  }" \
    "  return{vars,disabled,comments};" \
    " };" \
    " const parseLinesValid=raw=>String(raw||'').split(/\\r?\\n/).every(l=>!l.trim()||l.trim().startsWith('#')||/^[ \\t]*[A-Za-z_][A-Za-z0-9_]*[ \\t]*=/.test(l));" \
    " const activeVars=vars=>vars.filter(v=>v.key.trim()!==''||v.val!=='').map(v=>({key:v.key.trim(),val:v.val}));" \
    " const validateVars=vars=>{" \
    "  for(const v of vars){" \
    "   const k=v.key.trim();" \
    "   if(!k&&v.val==='')continue;" \
    "   if(!k||!keyOk(k))return false;" \
    "  }" \
    "  return true;" \
    " };" \
    " const serializeEnv=(vars,disabled,comments)=>{" \
    "  const lines=[...(comments||[]),...activeVars(vars).map(v=>v.key+'='+v.val)];" \
    "  if(!lines.length)return '';" \
    "  if(disabled)return [DISABLE_HDR,...lines.map(l=>l?'# '+l:'#')].join('\\n');" \
    "  return lines.join('\\n');" \
    " };" \
    " const serializeText=(vars,comments)=>[...(comments||[]),...activeVars(vars).map(v=>v.key+'='+v.val)].join('\\n');" \
    " const matchPreset=(presets,args,vars,disabled,comments)=>{" \
    "  if(disabled||(comments&&comments.length))return 'custom';" \
    "  const av=activeVars(vars),a=args||'';" \
    "  for(const k of Object.keys(presets)){" \
    "   const p=presets[k];" \
    "   if((p.args||'')!==a)continue;" \
    "   const pv=activeVars(p.vars||[]);" \
    "   if(pv.length!==av.length)continue;" \
    "   let same=true;" \
    "   for(let i=0;i<av.length;i++)if(pv[i].key!==av[i].key||pv[i].val!==av[i].val){same=false;break}" \
    "   if(same)return k;" \
    "  }" \
    "  return 'custom';" \
    " };" \
    " const autoResize=el=>{if(!el||!el.style)return;el.style.height='auto';el.style.height=el.scrollHeight+'px'};" \
    " const attach=(root,props)=>{" \
    "  if(root.npLO){root.npLO.sync(props);return}" \
    "  const doc=root.ownerDocument;" \
    "  const mk=(tag,cls,txt)=>{const n=doc.createElement(tag);if(cls)n.className=cls;if(txt!=null)n.textContent=txt;return n};" \
    "  const svg=(vb,w,h,body)=>{" \
    "   if(doc.createElementNS){" \
    "    const s=doc.createElementNS('http://www.w3.org/2000/svg','svg');" \
    "    s.setAttribute('viewBox',vb);s.setAttribute('width',w);s.setAttribute('height',h);" \
    "    s.setAttribute('fill','none');s.setAttribute('stroke','currentColor');s.setAttribute('stroke-width','2.2');s.setAttribute('stroke-linecap','round');s.setAttribute('stroke-linejoin','round');" \
    "    s.innerHTML=body;return s;" \
    "   }" \
    "   return mk('span','',body);" \
    "  };" \
    "  const header=mk('div','NPLOHeader');" \
    "  const title=mk('h3','NPLOTitle',props.title||'Launch Options');" \
    "  const presetWrap=mk('div','NPLOPresetWrap');" \
    "  const presetBtn=mk('button','NPLOPresetBtn');presetBtn.type='button';" \
    "  const presetLabel=mk('span','','Preset: Custom');" \
    "  const chevron=svg('0 0 24 24','14','14','<polyline points=\"6 9 12 15 18 9\"/>');" \
    "  if(chevron.className!==undefined&&typeof chevron.className==='string')chevron.className='NPLOPresetChevron';" \
    "  else if(chevron.setAttribute)chevron.setAttribute('class','NPLOPresetChevron');" \
    "  presetBtn.append(presetLabel,chevron);" \
    "  const popover=mk('div','NPLOPopover');popover.hidden=true;" \
    "  const presetList=mk('div','NPLOPresetList');" \
    "  const popFoot=mk('div','NPLOPopoverFoot');" \
    "  const addPresetBtn=mk('button','NPLOPresetAddBtn');addPresetBtn.type='button';" \
    "  addPresetBtn.append(mk('span','','+'),mk('span','','Save current as preset...'));" \
    "  const presetForm=mk('div','NPLOPresetForm');presetForm.hidden=true;" \
    "  const presetInput=mk('input','NPLOPresetInput');presetInput.type='text';presetInput.placeholder='Preset name...';" \
    "  const presetSaveBtn=mk('button','NPLOPresetSaveBtn','Save');presetSaveBtn.type='button';" \
    "  presetForm.append(presetInput,presetSaveBtn);" \
    "  popFoot.append(addPresetBtn,presetForm);" \
    "  popover.append(presetList,popFoot);" \
    "  presetWrap.append(presetBtn,popover);" \
    "  header.append(title,presetWrap);" \
    "  const argsBox=mk('div','NPLOArgsBox');" \
    "  const argsInput=mk('textarea','NPLOArgsInput');argsInput.rows=1;argsInput.spellcheck=false;" \
    "  argsInput.placeholder='Game arguments (e.g. %command% -novid -console)';" \
    "  argsInput.setAttribute('aria-label',props.title||'Launch Options');" \
    "  argsBox.append(argsInput);" \
    "  const card=mk('div','NPLOCard');" \
    "  const envBody=mk('div','NPLOEnvBody');" \
    "  const textWrap=mk('div','NPLOEnvTextWrap');textWrap.hidden=true;" \
    "  const textArea=mk('textarea','NPLOEnvText');textArea.rows=3;textArea.spellcheck=false;" \
    "  textArea.placeholder='KEY=VALUE (one per line)';" \
    "  textArea.setAttribute('aria-label','Per-game environment variables');" \
    "  textWrap.append(textArea);" \
    "  const statusRow=mk('div','NPLOStatus');statusRow.setAttribute('role','status');statusRow.hidden=true;" \
    "  const statusMsg=mk('span','');" \
    "  const retryBtn=mk('button','NPLOLink','Retry');retryBtn.type='button';retryBtn.hidden=true;" \
    "  statusRow.append(statusMsg,retryBtn);" \
    "  const foot=mk('div','NPLOFoot');" \
    "  const footL=mk('div','NPLOFootGroup');" \
    "  const footR=mk('div','NPLOFootGroup');" \
    "  const addVarBtn=mk('button','NPLOLink','+ Add variable');addVarBtn.type='button';" \
    "  const modeBtn=mk('button','NPLOLink','Edit as text');modeBtn.type='button';" \
    "  const bypassBtn=mk('button','NPLOLink','Disable');bypassBtn.type='button';" \
    "  const undoBtn=mk('button','NPLOLink','Undo clear');undoBtn.type='button';undoBtn.hidden=true;" \
    "  const clearBtn=mk('button','NPLOLink','Clear');clearBtn.type='button';" \
    "  footL.append(addVarBtn,modeBtn);footR.append(bypassBtn,undoBtn,clearBtn);" \
    "  foot.append(footL,footR);" \
    "  card.append(envBody,textWrap,statusRow,foot);" \
    "  root.replaceChildren(header,argsBox,card);" \
    "  const queues=globalThis.MSCXEnvWrites||(globalThis.MSCXEnvWrites=new Map);" \
    "  let cur=props,appId=props.appId,lastPropVal=props.value||'',presets=loadPresets(),activePreset='custom';" \
    "  let vars=[],comments=[],disabled=false,mode='list',loaded=false,dirty=false,revision=0,savedRaw='';" \
    "  let echo=[],valEls=[],nextRow=1,undoSnap=null,undoTimer=null,saveTimer=null,stopped=false,focusNewRow=false;" \
    "  const live=()=>!stopped&&root.isConnected&&root.firstChild===header;" \
    "  const setStatus=(msg,err,canRetry)=>{" \
    "   if(!live())return;" \
    "   if(!msg){statusRow.hidden=true;statusMsg.textContent='';retryBtn.hidden=true;return}" \
    "   statusRow.hidden=false;" \
    "   statusRow.className=err?'NPLOStatus error':'NPLOStatus';" \
    "   statusMsg.textContent=msg;" \
    "   retryBtn.hidden=!canRetry;" \
    "  };" \
    "  const syncArgsFromProps=val=>{" \
    "   const incoming=val||'';" \
    "   if(incoming===lastPropVal)return;" \
    "   lastPropVal=incoming;" \
    "   if(echo.length>0){" \
    "    const i=echo.indexOf(incoming);" \
    "    if(i===-1){echo.length=0;argsInput.value=incoming;autoResize(argsInput)}" \
    "    else{echo.splice(0,i+1)}" \
    "   }else if(incoming!==argsInput.value){argsInput.value=incoming;autoResize(argsInput)}" \
    "  };" \
    "  const commitArgs=val=>{" \
    "   if(val===argsInput.value&&echo.length===0&&val===(cur.value||''))return;" \
    "   argsInput.value=val;autoResize(argsInput);echo.push(val);cur.setValue?.(val);" \
    "  };" \
    "  const updatePresetUI=()=>{" \
    "   activePreset=matchPreset(presets,argsInput.value,vars,disabled,comments);" \
    "   presetLabel.textContent='Preset: '+(activePreset!=='custom'&&presets[activePreset]?presets[activePreset].label:'Custom');" \
    "   const keys=Object.keys(presets);" \
    "   if(!keys.length){" \
    "    const box=mk('div','NPLOPresetEmpty');" \
    "    const msg=mk('div','','No saved presets');msg.style.marginBottom='6px';" \
    "    const rst=mk('button','NPLOLink','Reset defaults');rst.type='button';" \
    "    rst.onclick=ev=>{ev.stopPropagation();presets=DEFAULTS();savePresets(presets);updatePresetUI()};" \
    "    box.append(msg,rst);presetList.replaceChildren(box);return;" \
    "   }" \
    "   presetList.replaceChildren(...keys.map(k=>{" \
    "    const row=mk('div','NPLOPresetItem');" \
    "    const pick=mk('button',k===activePreset?'NPLOPresetPick active':'NPLOPresetPick',presets[k].label);" \
    "    pick.type='button';" \
    "    pick.onclick=ev=>{ev.stopPropagation();applyPreset(k)};" \
    "    const del=mk('button','NPLOPresetDel');del.type='button';del.title='Delete preset';" \
    "    del.append(svg('0 0 24 24','13','13','<polyline points=\"3 6 5 6 21 6\"/><path d=\"M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6\"/><path d=\"M10 11v6M14 11v6\"/><path d=\"M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2\"/>'));" \
    "    del.onclick=ev=>{ev.stopPropagation();delete presets[k];savePresets(presets);updatePresetUI()};" \
    "    row.append(pick,del);return row;" \
    "   }));" \
    "  };" \
    "  const updateFooter=()=>{" \
    "   const hasArgs=argsInput.value.trim().length>0;" \
    "   const hasVars=vars.length>0;" \
    "   addVarBtn.hidden=mode==='text';" \
    "   modeBtn.textContent=mode==='text'?'Edit as list':'Edit as text';" \
    "   clearBtn.disabled=!hasArgs&&!hasVars&&!comments.length;" \
    "   bypassBtn.disabled=!loaded||!hasVars;" \
    "   bypassBtn.textContent=disabled?'Enable':'Disable';" \
    "   envBody.className=disabled?'NPLOEnvBody bypassed':'NPLOEnvBody';" \
    "   textWrap.className=disabled?'NPLOEnvTextWrap bypassed':'NPLOEnvTextWrap';" \
    "   envBody.hidden=mode==='text';" \
    "   textWrap.hidden=mode!=='text';" \
    "   addVarBtn.disabled=!loaded;" \
    "   modeBtn.disabled=!loaded;" \
    "   textArea.disabled=!loaded;" \
    "  };" \
    "  const saveEnvNow=()=>{" \
    "   if(saveTimer){clearTimeout(saveTimer);saveTimer=null}" \
    "   if(!loaded)return;" \
    "   let payload='';" \
    "   if(mode==='text'){" \
    "    const raw=textArea.value;" \
    "    if(!parseLinesValid(raw)||raw.includes('\\0')||new TextEncoder().encode(raw).length>65536){" \
    "     setStatus('Not saved. Use KEY=VALUE on each line (maximum 64 KiB).',true,false);return;" \
    "    }" \
    "    const p=parseText(raw);vars=p.vars.map(v=>({id:nextRow++,key:v.key,val:v.val}));comments=p.comments;" \
    "    payload=serializeEnv(vars,disabled,comments);" \
    "   }else{" \
    "    if(!validateVars(vars)){" \
    "     setStatus('Not saved. Use valid KEY=VALUE names (letters, digits, underscores).',true,false);return;" \
    "    }" \
    "    payload=serializeEnv(vars,disabled,comments);" \
    "    if(payload.includes('\\0')||new TextEncoder().encode(payload).length>65536){" \
    "     setStatus('Not saved. Environment exceeds 64 KiB limit.',true,false);return;" \
    "    }" \
    "   }" \
    "   if(payload===savedRaw&&!queues.has(appId)){dirty=false;setStatus('',false,false);return}" \
    "   if(typeof globalThis.MSCXSpecifyRoute!=='function'){return}" \
    "   const id=appId,rev=revision;" \
    "   dirty=false;" \
    "   setStatus('',false,false);" \
    "   const pending=Promise.resolve(queues.get(id)).catch(()=>{}).then(()=>globalThis.MSCXSpecifyRoute('NotProton.SetGameEnvironment#1',id,payload)).then(ans=>{" \
    "    if(!ans||ans.GetEResult()!==1)throw Error('save');" \
    "    if(id===appId){savedRaw=payload;if(rev===revision)setStatus('',false,false)}" \
    "   }).catch(()=>{" \
    "    if(id===appId&&rev===revision){dirty=true;setStatus('Could not save environment variables.',true,true)}" \
    "   });" \
    "   queues.set(id,pending);pending.finally(()=>{if(queues.get(id)===pending)queues.delete(id)});" \
    "  };" \
    "  const scheduleSave=()=>{" \
    "   revision++;dirty=true;" \
    "   if(saveTimer)clearTimeout(saveTimer);" \
    "   saveTimer=setTimeout(()=>saveEnvNow(),350);" \
    "  };" \
    "  const renderList=()=>{" \
    "   valEls=[];" \
    "   if(!vars.length){" \
    "    envBody.replaceChildren(mk('div','NPLOEnvEmpty','No environment variables configured.'));" \
    "   }else{" \
    "    let lastKeyEl=null;" \
    "    const rows=vars.map((item)=>{" \
    "     const row=mk('div','NPLOEnvRow');" \
    "     const fields=mk('div','NPLOEnvFields');" \
    "     const kIn=mk('input','NPLOEnvKey');kIn.type='text';kIn.spellcheck=false;" \
    "     kIn.placeholder='VARIABLE_NAME';kIn.value=item.key;" \
    "     kIn.setAttribute('aria-label','Variable name');" \
    "     const vIn=mk('textarea','NPLOEnvVal');vIn.rows=1;vIn.spellcheck=false;" \
    "     vIn.placeholder='Value';vIn.value=item.val;" \
    "     vIn.setAttribute('aria-label','Variable value');" \
    "     kIn.oninput=()=>{item.key=kIn.value;updatePresetUI();updateFooter();scheduleSave()};" \
    "     vIn.oninput=()=>{item.val=vIn.value;autoResize(vIn);updatePresetUI();updateFooter();scheduleSave()};" \
    "     kIn.onblur=()=>saveEnvNow();" \
    "     vIn.onblur=()=>saveEnvNow();" \
    "     const del=mk('button','NPLOEnvDel','\\u00d7');del.type='button';del.title='Remove variable';" \
    "     del.onclick=()=>{vars=vars.filter(x=>x.id!==item.id);if(!vars.length)disabled=false;revision++;dirty=true;renderList();updatePresetUI();updateFooter();saveEnvNow()};" \
    "     fields.append(kIn,vIn);row.append(fields,del);lastKeyEl=kIn;valEls.push(vIn);" \
    "     return row;" \
    "    });" \
    "    envBody.replaceChildren(...rows);" \
    "    valEls.forEach(autoResize);" \
    "    if(focusNewRow&&lastKeyEl){focusNewRow=false;lastKeyEl.focus?.()}" \
    "   }" \
    "   if(doc.activeElement!==textArea){textArea.value=serializeText(vars,comments);if(mode==='text')autoResize(textArea)}" \
    "   updateFooter();" \
    "  };" \
    "  const applyPreset=k=>{" \
    "   const p=presets[k];if(!p)return;" \
    "   commitArgs(p.args||'');" \
    "   vars=clone(p.vars||[]).map(v=>({id:nextRow++,key:v.key,val:v.val}));" \
    "   comments=[];disabled=false;revision++;dirty=true;" \
    "   if(mode==='text'){textArea.value=serializeText(vars,comments);autoResize(textArea)}" \
    "   renderList();updatePresetUI();closePopover();saveEnvNow();" \
    "  };" \
    "  const closePopover=()=>{popover.hidden=true;presetForm.hidden=true;addPresetBtn.hidden=false};" \
    "  const loadEnv=()=>{" \
    "   const id=appId;loaded=false;dirty=false;updateFooter();" \
    "   if(typeof globalThis.MSCXRoute!=='function'){loaded=true;vars=[];comments=[];disabled=false;savedRaw='';renderList();updatePresetUI();return}" \
    "   setStatus('Loading environment variables\\u2026',false,false);" \
    "   Promise.resolve(queues.get(id)).catch(()=>{}).then(()=>globalThis.MSCXRoute('NotProton.GetGameEnvironment#1',id)).then(txt=>{" \
    "    if(!live()||id!==appId)return;" \
    "    savedRaw=txt||'';" \
    "    const p=parseText(savedRaw);" \
    "    vars=p.vars.map(v=>({id:nextRow++,key:v.key,val:v.val}));" \
    "    comments=p.comments;disabled=p.disabled;loaded=true;dirty=false;" \
    "    setStatus('',false,false);" \
    "    if(mode==='text'){textArea.value=serializeText(vars,comments);autoResize(textArea)}" \
    "    renderList();updatePresetUI();" \
    "   }).catch(()=>{" \
    "    if(!live()||id!==appId)return;" \
    "    loaded=false;updateFooter();setStatus('Could not load environment variables.',true,true);" \
    "   });" \
    "  };" \
    "  presetBtn.onclick=ev=>{ev.stopPropagation();const show=popover.hidden;if(show){updatePresetUI();popover.hidden=false}else closePopover()};" \
    "  addPresetBtn.onclick=ev=>{ev.stopPropagation();addPresetBtn.hidden=true;presetForm.hidden=false;presetInput.value='';presetInput.focus?.()};" \
    "  presetInput.onclick=ev=>ev.stopPropagation();" \
    "  const confirmPreset=ev=>{ev?.stopPropagation();" \
    "   const name=presetInput.value.trim();if(!name){presetInput.focus?.();return}" \
    "   if(mode==='text'){const p=parseText(textArea.value);vars=p.vars.map(v=>({id:nextRow++,key:v.key,val:v.val}));comments=p.comments}" \
    "   let key='custom_'+Date.now();while(presets[key])key+='_1';" \
    "   presets[key]={label:name,args:argsInput.value,vars:activeVars(vars)};" \
    "   savePresets(presets);updatePresetUI();closePopover();" \
    "  };" \
    "  presetSaveBtn.onclick=confirmPreset;" \
    "  presetInput.onkeydown=ev=>{if(ev.key==='Enter')confirmPreset(ev);else if(ev.key==='Escape')closePopover()};" \
    "  argsInput.oninput=()=>{autoResize(argsInput);echo.push(argsInput.value);cur.setValue?.(argsInput.value);updatePresetUI();updateFooter()};" \
    "  addVarBtn.onclick=()=>{if(!loaded)return;vars.push({id:nextRow++,key:'',val:''});focusNewRow=true;renderList();updatePresetUI()};" \
    "  modeBtn.onclick=()=>{" \
    "   if(!loaded)return;" \
    "   if(mode==='list'){" \
    "    mode='text';textArea.value=serializeText(vars,comments);updateFooter();autoResize(textArea);textArea.focus?.();" \
    "   }else{" \
    "    const p=parseText(textArea.value);" \
    "    vars=p.vars.map(v=>({id:nextRow++,key:v.key,val:v.val}));comments=p.comments;" \
    "    mode='list';renderList();updatePresetUI();saveEnvNow();" \
    "   }" \
    "  };" \
    "  textArea.oninput=()=>{" \
    "   autoResize(textArea);" \
    "   if(parseLinesValid(textArea.value)){const p=parseText(textArea.value);vars=p.vars.map(v=>({id:nextRow++,key:v.key,val:v.val}));comments=p.comments;updatePresetUI();updateFooter()}" \
    "   scheduleSave();" \
    "  };" \
    "  textArea.onblur=()=>saveEnvNow();" \
    "  bypassBtn.onclick=()=>{if(!loaded||!vars.length)return;disabled=!disabled;revision++;dirty=true;updatePresetUI();updateFooter();saveEnvNow()};" \
    "  clearBtn.onclick=()=>{" \
    "   if(!loaded)return;" \
    "   undoSnap={args:argsInput.value,vars:clone(vars),comments:clone(comments),disabled};" \
    "   commitArgs('');vars=[];comments=[];disabled=false;revision++;dirty=true;" \
    "   textArea.value='';if(mode==='text')autoResize(textArea);" \
    "   renderList();updatePresetUI();saveEnvNow();" \
    "   undoBtn.hidden=false;if(undoTimer)clearTimeout(undoTimer);" \
    "   undoTimer=setTimeout(()=>{undoBtn.hidden=true;undoSnap=null},8000);" \
    "  };" \
    "  undoBtn.onclick=()=>{" \
    "   if(!undoSnap)return;" \
    "   const s=undoSnap;undoSnap=null;if(undoTimer){clearTimeout(undoTimer);undoTimer=null}undoBtn.hidden=true;" \
    "   commitArgs(s.args);vars=s.vars;comments=s.comments;disabled=s.disabled;revision++;dirty=true;" \
    "   if(mode==='text'){textArea.value=serializeText(vars,comments);autoResize(textArea)}" \
    "   renderList();updatePresetUI();saveEnvNow();" \
    "  };" \
    "  retryBtn.onclick=()=>{if(!loaded)loadEnv();else saveEnvNow()};" \
    "  const onDocClick=ev=>{if(!presetWrap.contains?.(ev.target))closePopover()};" \
    "  doc.addEventListener?.('click',onDocClick);" \
    "  const ro=typeof ResizeObserver==='function'?new ResizeObserver(()=>{autoResize(argsInput);if(mode==='text')autoResize(textArea);else valEls.forEach(autoResize)}):null;" \
    "  ro?.observe(root);" \
    "  const obs=globalThis.MutationObserver?new globalThis.MutationObserver(()=>{if(!root.isConnected){" \
    "   if(dirty)saveEnvNow();stopped=true;if(undoTimer)clearTimeout(undoTimer);if(saveTimer)clearTimeout(saveTimer);" \
    "   doc.removeEventListener?.('click',onDocClick);ro?.disconnect();obs.disconnect()" \
    "  }}):null;" \
    "  obs?.observe(doc,{childList:true,subtree:true});" \
    "  root.npLO={sync(np){" \
    "   cur=np;title.textContent=np.title||'Launch Options';" \
    "   if(np.appId!==appId){appId=np.appId;lastPropVal=np.value||'';echo.length=0;vars=[];comments=[];disabled=false;savedRaw='';undoSnap=null;undoBtn.hidden=true;argsInput.value=lastPropVal;autoResize(argsInput);renderList();loadEnv();return}" \
    "   syncArgsFromProps(np.value);updatePresetUI();updateFooter();" \
    "  }};" \
    "  argsInput.value=props.value||'';autoResize(argsInput);updatePresetUI();loadEnv();" \
    " };" \
    " return np=>react().jsxs('div',{className:'NPLOSection'+(np.className?' '+np.className:''),children:[" \
    "  react().jsx('style',{children:\"" NP_LO_CSS "\"})," \
    "  np.extra||null," \
    "  react().jsx('div',{className:'NPLOHost',ref:e=>e&&attach(e,np)},'lo-'+np.appId)" \
    " ]});" \
    "})(()=>" RT ",()=>" BARREL ")"

#endif
