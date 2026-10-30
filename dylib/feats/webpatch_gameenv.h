// Append to the per-game panel without changing the shared settings layout.
#ifndef NOTPROTON_WEBPATCH_GAMEENV_H
#define NOTPROTON_WEBPATCH_GAMEENV_H
#define NP_CX_GAME_ENV(RT, BARREL) \
    "((react,ui)=>{" \
    " const base=" NP_CX_OPTIONS_BODY("react()", "ui()") ";" \
    " const attach=(root,id)=>{" \
    "  if(root.npEnvApp===id)return;" \
    "  root.npEnvApp=id;" \
    "  const doc=root.ownerDocument,field=doc.createElement('textarea'),status=doc.createElement('div'),retry=doc.createElement('button');" \
    "  field.className='MSCXEnvField';field.rows=6;field.spellcheck=false;field.disabled=true;" \
    "  field.setAttribute('aria-label','Per-game environment variables');" \
    "  field.placeholder='FOO=bar\\nDXMT_CONFIG=d3d11.example=1';" \
    "  status.className='MSCXEnvHint';status.setAttribute('role','status');" \
    "  retry.className='MSCXBtn';retry.textContent='Retry';retry.hidden=true;" \
    "  root.replaceChildren(field,status,retry);" \
    "  const queues=globalThis.MSCXEnvWrites||(globalThis.MSCXEnvWrites=new Map);" \
    "  const live=()=>root.isConnected&&root.npEnvApp===id&&root.firstChild===field;" \
    "  let saved='',revision=0;" \
    "  const show=text=>{if(live())status.textContent=text};" \
    "  const load=()=>{retry.hidden=true;show('Loading environment variables…');" \
    "   Promise.resolve(queues.get(id)).catch(()=>{}).then(()=>globalThis.MSCXRoute('NotProton.GetGameEnvironment#1',id)).then(text=>{" \
    "    if(!live())return;saved=text;field.value=text;field.disabled=false;" \
    "    show('One KEY=VALUE per line. Values are literal. Blank lines and # comments are ignored. Saved when you leave this field; restart the game to apply.');" \
    "   }).catch(()=>{show('Could not load environment variables.');if(live())retry.hidden=false});" \
    "  };" \
    "  field.oninput=()=>{revision++;show('Unsaved changes.')};" \
    "  field.onblur=()=>{" \
    "   const text=field.value,rev=revision;if(field.disabled||(text===saved&&!queues.has(id)))return;" \
    "   const valid=text.split(/\\r?\\n/).every(line=>!line.trim()||line.trim().startsWith('#')||/^[ \\t]*[A-Za-z_][A-Za-z0-9_]*[ \\t]*=/.test(line));" \
    "   if(!valid||text.includes('\\0')||new TextEncoder().encode(text).length>65536){show('Not saved. Use KEY=VALUE on each line (maximum 64 KiB).');return}" \
    "   show('Saving…');" \
    "   const pending=Promise.resolve(queues.get(id)).catch(()=>{}).then(()=>globalThis.MSCXSpecifyRoute('NotProton.SetGameEnvironment#1',id,text)).then(answer=>{" \
    "    if(answer.GetEResult()!==1)throw Error('save');saved=text;if(rev===revision)show('Saved. Restart the game to apply.');" \
    "   }).catch(()=>{if(rev===revision)show('Could not save. Leave the field again to retry.');});" \
    "   queues.set(id,pending);pending.finally(()=>{if(queues.get(id)===pending)queues.delete(id)});" \
    "  };" \
    "  retry.onclick=load;load();" \
    " };" \
    " return np=>{" \
    "  const panel=base(np);if(!panel)return null;" \
    "  const section=react().jsx(ui().XY,{label:'Environment variables',children:[" \
    "   react().jsx('style',{children:'.MSCXEnvField{box-sizing:border-box;display:block;width:100%;min-width:0;min-height:132px;resize:vertical;padding:10px;color:#dfe3e6;background:rgba(13,15,18,.72);border:1px solid rgba(130,140,150,.35);border-radius:3px;font:12px/1.5 monospace;white-space:pre}.MSCXEnvField:focus{outline:1px solid #66c0f4;outline-offset:-1px;border-color:#66c0f4}.MSCXEnvField:disabled{opacity:.6}.MSCXEnvHint{margin:6px 0;color:#a7adb4;font-size:12px;line-height:1.4}'})," \
    "   react().jsx('div',{className:'MSCXEnvEditor',ref:e=>e&&attach(e,np.details.unAppID)},'env-'+np.details.unAppID)" \
    "  ]},'env');" \
    "  return react().jsx('div',{className:'MSCXPanel',children:react().jsxs(react().Fragment,{children:panel.props.children.props.children.concat([section])})});" \
    " };" \
    "})(()=>" RT ",()=>" BARREL ")"
#endif
