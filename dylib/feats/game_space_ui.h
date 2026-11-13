#ifndef NOTPROTON_GAME_SPACE_UI_H
#define NOTPROTON_GAME_SPACE_UI_H

#define NP_GAME_SPACE_ROW(RT) \
    "(0," RT ".jsx)(\"section\",{className:\"MSCXRow\",\"aria-label\":\"Game resolution\",ref:e=>{if(!e)return;" \
    "const value=g(\"NOTPROTON_NATIVE_SIZE\"),mode=g(\"NOTPROTON_NATIVE_SIZE_MODE\");" \
    "e.npSave=s=>L.s([[\"NOTPROTON_NATIVE_SIZE\",s],[\"NOTPROTON_NATIVE_SIZE_MODE\",e.querySelector(\"select\").value===\"custom\"?\"custom\":\"\"]]);" \
    "const cache=t.unAppID+\"/\"+value+\"/\"+mode;if(e.npValue===cache)return;e.npValue=cache;e.replaceChildren();" \
    "const sizes=[\"320x200\",\"320x240\",\"400x300\",\"512x384\",\"640x360\",\"640x480\",\"720x480\",\"720x576\",\"800x600\",\"854x480\",\"960x540\",\"1024x576\",\"1024x768\",\"1152x864\",\"1280x720\",\"1280x800\",\"1280x960\",\"1280x1024\",\"1360x768\",\"1366x768\",\"1440x900\",\"1600x900\",\"1600x1200\",\"1680x1050\",\"1920x1080\",\"1920x1200\",\"1920x1440\",\"2048x1152\",\"2048x1536\",\"2560x1080\",\"2560x1440\",\"2560x1600\",\"2880x1620\",\"2880x1800\",\"3200x1800\",\"3440x1440\",\"3840x1600\",\"3840x2160\",\"1080x1920\"].sort((a,b)=>{a=a.split(\"x\").map(Number);b=b.split(\"x\").map(Number);return a[0]*a[1]-b[0]*b[1]||a[0]-b[0]});" \
    "const make=(tag,text)=>{const n=document.createElement(tag);if(text)n.textContent=text;return n}," \
    "box=make(\"div\"),label=make(\"label\",\"Game resolution\"),select=make(\"select\"),custom=make(\"div\")," \
    "width=make(\"input\"),height=make(\"input\"),apply=make(\"button\",\"Apply\"),status=make(\"span\")," \
    "description=make(\"div\",\"Fixed game-window size in pixels, presented in a native macOS fullscreen Space. The Mac display is not changed. Applies next launch. Games may override their internal rendering resolution.\");" \
    "box.style.cssText=\"width:100%;display:flex;flex-direction:column;gap:8px\";" \
    "label.style.fontWeight=\"500\";label.append(select);select.style.cssText=\"margin-left:16px;max-width:100%;padding:6px;color:inherit;background:#232d3b;border:1px solid #536173;border-radius:3px\";" \
    "[[\"\",\"Off (game controlled)\"],...sizes.map(x=>[x,x.replace(\"x\",\" \\u00d7 \")]),[\"custom\",\"Custom...\"]].forEach(([v,t])=>{const o=make(\"option\",t);o.value=v;select.append(o)});" \
    "select.value=mode===\"custom\"||value&&!sizes.includes(value)?\"custom\":value;" \
    "const parts=(value||\"1920x1080\").split(\"x\");[width,height].forEach((n,i)=>{n.type=\"number\";n.min=\"200\";n.max=\"16384\";n.step=\"1\";n.value=parts[i]||\"\";n.setAttribute(\"aria-label\",i?\"Height in pixels\":\"Width in pixels\");n.style.cssText=\"width:100px;padding:6px;color:inherit;background:#17212e;border:1px solid #536173;border-radius:3px\"});width.min=\"320\";" \
    "custom.style.cssText=\"display:flex;align-items:center;flex-wrap:wrap;gap:8px\";" \
    "status.setAttribute(\"role\",\"status\");description.style.cssText=\"font-size:12px;color:#adb7c5\";" \
    "const valid=()=>width.validity.valid&&height.validity.valid&&width.value!==\"\"&&height.value!==\"\",update=()=>{const on=select.value===\"custom\";width.disabled=height.disabled=!on;apply.disabled=!on||!valid();custom.style.opacity=on?\"1\":\".5\"};" \
    "select.onchange=()=>{status.textContent=\"\";update();if(select.value!==\"custom\")e.npSave(select.value);else width.focus()};" \
    "width.oninput=height.oninput=()=>{status.textContent=valid()?\"Press Apply to save\":\"Width: 320-16384; height: 200-16384 pixels\";update()};" \
    "apply.type=\"button\";apply.onclick=()=>{if(valid()){e.npSave(Number(width.value)+\"x\"+Number(height.value));status.textContent=\"Applies next launch\"}};" \
    "custom.onkeydown=x=>{if(x.key===\"Enter\"&&!apply.disabled){x.preventDefault();apply.click()}};" \
    "custom.append(width,make(\"span\",\"\\u00d7\"),height,apply,status);box.append(label,custom,description);e.append(box);update();" \
    "}},\"native-game-space\")"

#endif
