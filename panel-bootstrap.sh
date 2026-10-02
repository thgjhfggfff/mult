#!/bin/bash
set -u

CONFIG_FILE="/etc/x-ui/config.json"
LOG() { echo "[panel-bootstrap] $*"; }

PANEL_BASE_PATH=$(jq -r '.xui.web_base_path' "$CONFIG_FILE")
PANEL_INTERNAL="http://127.0.0.1:$(jq -r '.xui.internal_port' "$CONFIG_FILE")${PANEL_BASE_PATH}"
PANEL_USER="${XUI_USERNAME:-$(jq -r '.xui.default_username' "$CONFIG_FILE")}"
PANEL_PASS="${XUI_PASSWORD:-$(jq -r '.xui.default_password' "$CONFIG_FILE")}"
API_TOKEN="${XUI_API_TOKEN:-}"


DIRECT_ENABLED=$(jq -r '.direct.enabled // true' "$CONFIG_FILE")
DIRECT_PORT=$(jq -r '.direct.port // 8080' "$CONFIG_FILE")
DIRECT_PATH=$(jq -r '.direct.path // "/direct"' "$CONFIG_FILE")
DIRECT_TAG=$(jq -r '.direct.tag // "direct-inbound"' "$CONFIG_FILE")

COOKIE_JAR="/tmp/xui-cookies.txt"
CSRF_TOKEN=""

XUI_BIN="/usr/local/x-ui/x-ui"

detect_domain() {
    if [ -n "${PUBLIC_DOMAIN:-}" ]; then
        echo "$PUBLIC_DOMAIN"
    elif [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
        echo "$RAILWAY_PUBLIC_DOMAIN"
    elif [ -n "${RAILWAY_STATIC_URL:-}" ]; then
        echo "$RAILWAY_STATIC_URL" | sed -E 's~^https?://~~'
    else
        NGINX_PUBLIC_PORT=$(jq -r '.server.public_port // 3000' "$CONFIG_FILE")
        echo "localhost:${NGINX_PUBLIC_PORT}"
    fi
}

DOMAIN="$(detect_domain)"
LOG "Detected public domain: $DOMAIN"

# Subscription token: the SAME subId is given to every client, so one subscription URL
# returns all configs (Direct + every verified country). Set SUB_ID in Railway variables
# to choose your own value; otherwise a stable one is derived (same after every redeploy).
if [ -n "${SUB_ID:-}" ]; then
    SUB_TOKEN="$SUB_ID"
else
    SUB_TOKEN=$(printf '%s' "${PANEL_PASS}:${DOMAIN}:sub" | sha256sum | cut -c1-16)
fi

# Pretty page shown when the subscription link is opened in a browser
# (nginx serves it only to browsers; apps like v2rayN/v2rayNG still get the raw subscription).
mkdir -p /var/www/sub-ui
cat > /var/www/sub-ui/index.html <<'SUBUI_EOF'
<!DOCTYPE html>
<html lang="fa" dir="rtl" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex,nofollow">
<meta name="color-scheme" content="dark light">
<title>اشتراک شما</title>
<style>
:root{
  --bg1:#070b1a;--bg2:#150f35;--card:rgba(255,255,255,.09);--card2:rgba(255,255,255,.06);--line:rgba(255,255,255,.18);
  --txt:#ffffff;--sub:#d6dcff;--mut:#b4bce6;--a:#8b6cff;--b:#22d3ee;--ok:#4ade80;--err:#ff9db1;--chipbg:rgba(74,222,128,.16);
  --btnTxt:#ffffff;--shadow:0 10px 30px rgba(0,0,0,.35);--orb1:#6d4cff66;--orb2:#06b6d455
}
[data-theme="light"]{
  --bg1:#f4f6ff;--bg2:#e6e9ff;--card:rgba(255,255,255,.88);--card2:rgba(255,255,255,.95);--line:rgba(30,41,120,.16);
  --txt:#0d1240;--sub:#2c356e;--mut:#4b5590;--a:#6d4cff;--b:#0891b2;--ok:#15803d;--err:#be123c;--chipbg:rgba(21,128,61,.12);
  --btnTxt:#ffffff;--shadow:0 10px 26px rgba(40,50,140,.15);--orb1:#7c5cff33;--orb2:#22d3ee33
}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{margin:0;min-height:100%}
body{font-family:system-ui,-apple-system,"Segoe UI",Tahoma,"Noto Sans Arabic","Noto Naskh Arabic",sans-serif;color:var(--txt);font-size:16px;line-height:1.6;
  background:linear-gradient(160deg,var(--bg1),var(--bg2));background-attachment:fixed;position:relative;overflow-x:hidden;
  padding:max(16px,env(safe-area-inset-top)) 16px max(34px,env(safe-area-inset-bottom))}
.orb{position:fixed;border-radius:50%;filter:blur(70px);z-index:0;pointer-events:none}
.o1{width:320px;height:320px;background:var(--orb1);top:-90px;right:-80px;animation:fl 14s ease-in-out infinite alternate}
.o2{width:300px;height:300px;background:var(--orb2);bottom:-90px;left:-90px;animation:fl 17s ease-in-out infinite alternate-reverse}
@keyframes fl{to{transform:translate(30px,40px) scale(1.15)}}
.wrap{max-width:580px;margin:0 auto;position:relative;z-index:1}
.top{display:flex;justify-content:space-between;align-items:center;margin-bottom:4px}
.chip{display:inline-flex;align-items:center;gap:8px;background:var(--chipbg);color:var(--ok);border:1px solid var(--line);padding:6px 14px;border-radius:99px;font-size:14px;font-weight:700}
.chip i{width:9px;height:9px;border-radius:50%;background:var(--ok);box-shadow:0 0 0 0 var(--ok);animation:pu 1.8s infinite}
@keyframes pu{70%{box-shadow:0 0 0 8px transparent}100%{box-shadow:0 0 0 0 transparent}}
.theme{appearance:none;border:1px solid var(--line);background:var(--card);color:var(--txt);width:44px;height:44px;border-radius:14px;font-size:20px;cursor:pointer;line-height:1}
.hero{text-align:center;padding:14px 6px 12px}
.logo{width:84px;height:84px;border-radius:28px;margin:0 auto 14px;display:grid;place-items:center;font-size:42px;color:#fff;
  background:linear-gradient(135deg,var(--a),var(--b));box-shadow:0 14px 36px rgba(109,76,255,.45)}
h1{margin:0 0 6px;font-size:28px;font-weight:800;letter-spacing:-.3px}
.sub{color:var(--sub);font-size:16px;margin:0;font-weight:500;min-height:26px}
.card{background:var(--card);border:1px solid var(--line);border-radius:22px;padding:18px;margin-top:16px;box-shadow:var(--shadow);backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px)}
h2{font-size:17px;margin:0 0 14px;color:var(--txt);font-weight:800;display:flex;align-items:center;gap:8px}
h2:before{content:"";width:5px;height:18px;border-radius:4px;background:linear-gradient(var(--a),var(--b))}
.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
.stat{background:var(--card2);border:1px solid var(--line);border-radius:16px;padding:14px 6px;text-align:center}
.stat em{font-style:normal;font-size:20px;display:block;margin-bottom:2px}
.stat b{display:block;font-size:20px;font-weight:800;direction:ltr;color:var(--txt)}
.stat span{font-size:14px;color:var(--sub);font-weight:600}
.bar{height:10px;background:var(--line);border-radius:99px;overflow:hidden;margin-top:16px;display:none}
.bar i{display:block;height:100%;width:0;background:linear-gradient(90deg,var(--a),var(--b));border-radius:99px;transition:width .8s}
.btn{appearance:none;border:0;cursor:pointer;font:inherit;font-size:16px;color:var(--btnTxt);border-radius:16px;padding:15px 14px;width:100%;font-weight:800;
  background:linear-gradient(135deg,var(--a),#5b8cff);box-shadow:0 10px 24px rgba(91,91,255,.4);transition:transform .12s}
.btn:active{transform:scale(.97)}
.btn.ghost{background:var(--card2);color:var(--txt);box-shadow:none;border:1px solid var(--line);font-weight:700}
.row{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:12px}
.apps{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
.apps a{display:block;text-align:center;text-decoration:none;color:var(--txt);font-size:15px;font-weight:700;padding:14px 6px;border-radius:16px;background:var(--card2);border:1px solid var(--line)}
.apps a:active{transform:scale(.96)}
.cfg{display:flex;align-items:center;gap:12px;padding:12px;border-radius:18px;background:var(--card2);border:1px solid var(--line);margin-bottom:10px}
.cfg .fl{width:50px;height:50px;border-radius:16px;display:grid;place-items:center;font-size:28px;flex:none;background:linear-gradient(135deg,rgba(139,108,255,.28),rgba(34,211,238,.22));border:1px solid var(--line)}
.cfg .n{flex:1;min-width:0}
.cfg .t{font-weight:800;font-size:17px;color:var(--txt);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.cfg .p{display:inline-block;margin-top:3px;font-size:12px;font-weight:800;color:var(--b);border:1px solid var(--line);padding:0 8px;border-radius:99px;direction:ltr}
.cfg button{appearance:none;border:1px solid var(--line);background:linear-gradient(135deg,var(--a),#5b8cff);color:#fff;border-radius:12px;padding:10px 16px;font:inherit;font-size:15px;font-weight:800;cursor:pointer}
.cfg button.done{background:var(--ok);border-color:transparent;color:#052e16}
.cfg button:active{transform:scale(.95)}
.msg{text-align:center;color:var(--sub);padding:20px 6px;font-size:16px;font-weight:600}
.err{color:var(--err)}
.toast{position:fixed;left:50%;bottom:max(26px,env(safe-area-inset-bottom));transform:translate(-50%,40px);opacity:0;background:#0f172a;color:#fff;border:1px solid var(--line);
  padding:12px 22px;border-radius:99px;font-size:15px;font-weight:700;transition:.25s;pointer-events:none;z-index:9}
.toast.on{opacity:1;transform:translate(-50%,0)}
.foot{text-align:center;color:var(--mut);font-size:14px;margin-top:20px;font-weight:500}
</style>
</head>
<body>
<div class="orb o1"></div><div class="orb o2"></div>
<div class="wrap">
  <div class="top">
    <span class="chip"><i></i>فعال</span>
    <button class="theme" id="theme" aria-label="تغییر تم">🌙</button>
  </div>

  <div class="hero">
    <div class="logo">⚡</div>
    <h1>اشتراک شما</h1>
    <p class="sub" id="sub">در حال دریافت کانفیگ‌ها…</p>
  </div>

  <div class="card">
    <div class="stats">
      <div class="stat"><em>🌍</em><b id="sCount">–</b><span>لوکیشن</span></div>
      <div class="stat"><em>📊</em><b id="sUsed">–</b><span>مصرف</span></div>
      <div class="stat"><em>♾️</em><b id="sTotal">–</b><span>حجم کل</span></div>
    </div>
    <div class="bar" id="bar"><i id="barFill"></i></div>
  </div>

  <div class="card">
    <h2>افزودن به برنامه</h2>
    <div class="apps">
      <a id="aNG" href="#">v2rayNG</a>
      <a id="aHid" href="#">Hiddify</a>
      <a id="aStr" href="#">Streisand</a>
    </div>
    <div class="row">
      <button class="btn" id="copySub">📋 کپی لینک اشتراک</button>
      <button class="btn ghost" id="copyAll">کپی همه کانفیگ‌ها</button>
    </div>
  </div>

  <div class="card">
    <h2>لوکیشن‌ها</h2>
    <div id="list"><div class="msg">در حال بارگذاری…</div></div>
  </div>

  <div class="foot">برای به‌روزرسانی، تو برنامه‌ات «Update subscription» رو بزن.</div>
</div>
<div class="toast" id="toast"></div>

<script>
(function(){
  var $=function(i){return document.getElementById(i)};
  var subUrl=location.origin+location.pathname;
  var links=[];

  // theme (dark by default, remembered if storage is available)
  var root=document.documentElement;
  function setTheme(t){root.setAttribute('data-theme',t);$('theme').textContent=t==='dark'?'🌙':'☀️'}
  var saved=null;try{saved=localStorage.getItem('sub-theme')}catch(e){}
  setTheme(saved==='light'?'light':'dark');
  $('theme').onclick=function(){
    var t=root.getAttribute('data-theme')==='dark'?'light':'dark';setTheme(t);
    try{localStorage.setItem('sub-theme',t)}catch(e){}
  };

  function toast(t){var e=$('toast');e.textContent=t;e.classList.add('on');clearTimeout(toast.t);toast.t=setTimeout(function(){e.classList.remove('on')},1600)}
  function copy(text,cb){
    function ok(){toast('کپی شد ✓');if(cb)cb()}
    function fallback(){var a=document.createElement('textarea');a.value=text;a.style.position='fixed';a.style.opacity='0';document.body.appendChild(a);a.select();
      try{document.execCommand('copy');ok()}catch(e){toast('کپی نشد')}document.body.removeChild(a)}
    if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(text).then(ok,fallback)}else fallback();
  }
  function fmt(b){if(!isFinite(b)||b<=0)return '0';var u=['B','KB','MB','GB','TB'],i=0;while(b>=1024&&i<u.length-1){b/=1024;i++}return (b>=100?b.toFixed(0):b.toFixed(1))+' '+u[i]}

  function decodeBody(txt){
    txt=(txt||'').trim();
    if(/^[a-z][a-z0-9+.-]*:\/\//i.test(txt))return txt;
    try{
      var bin=atob(txt.replace(/\s+/g,'').replace(/-/g,'+').replace(/_/g,'/'));
      var bytes=Uint8Array.from(bin,function(c){return c.charCodeAt(0)});
      return new TextDecoder('utf-8').decode(bytes);
    }catch(e){return ''}
  }
  // split "🇩🇪 ɢᴇʀᴍᴀɴʏ-ᴠɪᴘ" into flag + text
  function splitName(n){
    var m=null;
    try{m=n.match(/^((?:\p{Regional_Indicator}{2})|\p{Extended_Pictographic}\uFE0F?)\s*([\s\S]*)$/u)}catch(e){}
    return m?{flag:m[1],text:m[2]||n}:{flag:'🌐',text:n};
  }
  function parse(txt){
    return decodeBody(txt).split(/\r?\n/).map(function(s){return s.trim()}).filter(function(s){return /^[a-z][a-z0-9+.-]*:\/\//i.test(s)}).map(function(l){
      var h=l.indexOf('#'),name='کانفیگ',proto=l.split('://')[0];
      if(h>-1){try{name=decodeURIComponent(l.slice(h+1))||name}catch(e){name=l.slice(h+1)}}
      var s=splitName(name);
      return {link:l,flag:s.flag,name:s.text,proto:proto.toUpperCase()};
    });
  }

  function render(){
    var box=$('list');box.textContent='';
    if(!links.length){var d=document.createElement('div');d.className='msg err';d.textContent='کانفیگی پیدا نشد. لینک اشتراک درست نیست یا هنوز آماده نشده.';box.appendChild(d);return}
    links.forEach(function(c){
      var row=document.createElement('div');row.className='cfg';
      var f=document.createElement('div');f.className='fl';f.textContent=c.flag;
      var n=document.createElement('div');n.className='n';
      var t=document.createElement('div');t.className='t';t.textContent=c.name;
      var p=document.createElement('span');p.className='p';p.textContent=c.proto;
      n.appendChild(t);n.appendChild(p);
      var b=document.createElement('button');b.textContent='کپی';
      b.onclick=function(){copy(c.link,function(){b.textContent='✓';b.className='done';setTimeout(function(){b.textContent='کپی';b.className=''},1400)})};
      row.appendChild(f);row.appendChild(n);row.appendChild(b);box.appendChild(row);
    });
  }

  function stats(h){
    $('sCount').textContent=links.length;
    var info=h&&h.get('subscription-userinfo');
    if(!info){$('sUsed').textContent='–';$('sTotal').textContent='نامحدود';return}
    var o={};info.split(';').forEach(function(p){var k=p.split('=');if(k.length>1)o[k[0].trim()]=Number(k[1])});
    var used=(o.upload||0)+(o.download||0),total=o.total||0;
    $('sUsed').textContent=fmt(used);
    if(total>0){$('sTotal').textContent=fmt(total);$('bar').style.display='block';$('barFill').style.width=Math.min(100,used/total*100)+'%'}
    else $('sTotal').textContent='نامحدود';
    if(o.expire>0){$('sub').textContent='انقضا: '+new Date(o.expire*1000).toLocaleDateString('fa-IR')}
  }

  var enc=encodeURIComponent(subUrl);
  $('aNG').href='v2rayng://install-sub?url='+enc+'&name='+encodeURIComponent('اشتراک');
  $('aHid').href='hiddify://import/'+subUrl+'#'+encodeURIComponent('اشتراک');
  $('aStr').href='streisand://import/'+subUrl;
  $('copySub').onclick=function(){copy(subUrl)};
  $('copyAll').onclick=function(){if(links.length)copy(links.map(function(c){return c.link}).join('\n'));else toast('کانفیگی نیست')};

  fetch(subUrl,{cache:'no-store',headers:{'Accept':'*/*'}}).then(function(r){
    if(!r.ok)throw new Error(r.status);
    return r.text().then(function(t){
      links=parse(t);
      $('sub').textContent=links.length?'همه لوکیشن‌ها تو یک لینک':'';
      render();stats(r.headers)});
  }).catch(function(){
    $('sub').textContent='';
    var box=$('list');box.textContent='';var d=document.createElement('div');d.className='msg err';d.textContent='دریافت اشتراک ممکن نشد. لینک رو چک کن.';box.appendChild(d);
    $('sCount').textContent='0';
  });
})();
</script>
</body>
</html>
SUBUI_EOF
chmod -R a+rX /var/www/sub-ui

wait_for_panel() {
    for i in $(seq 1 30); do
        code=$(curl -s -o /dev/null -w "%{http_code}" "${PANEL_INTERNAL}/login")
        if [ "$code" != "000" ]; then
            LOG "Panel is responding (http $code)."
            return 0
        fi
        sleep 2
    done
    LOG "❌ Panel never responded. Aborting."
    return 1
}

login() {
    if [ -n "$API_TOKEN" ]; then
        LOG "✅ Using XUI_API_TOKEN (Bearer auth)."
        return 0
    fi

    csrf_resp=$(curl -s -c "$COOKIE_JAR" "${PANEL_INTERNAL}/csrf-token")
    CSRF_TOKEN=$(echo "$csrf_resp" | jq -r '.obj // .token // empty' 2>/dev/null)

    json_data=$(jq -n --arg u "$PANEL_USER" --arg p "$PANEL_PASS" '{username:$u,password:$p}')
    if [ -n "$CSRF_TOKEN" ]; then
        resp=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
            -H "Content-Type: application/json" -H "X-CSRF-Token: ${CSRF_TOKEN}" \
            -X POST "${PANEL_INTERNAL}/login" -d "$json_data")
    else
        resp=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
            -H "Content-Type: application/json" \
            -X POST "${PANEL_INTERNAL}/login" -d "$json_data")
    fi

    ok=$(echo "$resp" | jq -r '.success // empty' 2>/dev/null)
    if [ "$ok" != "true" ]; then
        LOG "❌ Login failed. Response: '${resp}'"
        return 1
    fi
    LOG "✅ Logged into panel API."
    return 0
}

api_post() {
    local path="$1" data="$2"
    if [ -n "$API_TOKEN" ]; then
        curl -s -H "Content-Type: application/json" -H "Authorization: Bearer ${API_TOKEN}" \
            -X POST "${PANEL_INTERNAL}${path}" -d "$data"
    elif [ -n "$CSRF_TOKEN" ]; then
        curl -s -b "$COOKIE_JAR" -H "Content-Type: application/json" \
            -H "X-CSRF-Token: ${CSRF_TOKEN}" -X POST "${PANEL_INTERNAL}${path}" -d "$data"
    else
        curl -s -b "$COOKIE_JAR" -H "Content-Type: application/json" \
            -X POST "${PANEL_INTERNAL}${path}" -d "$data"
    fi
}

api_post_form() {
    local path="$1"; shift
    if [ -n "$API_TOKEN" ]; then
        curl -s -H "Authorization: Bearer ${API_TOKEN}" \
            -X POST "${PANEL_INTERNAL}${path}" "$@"
    elif [ -n "$CSRF_TOKEN" ]; then
        curl -s -b "$COOKIE_JAR" -H "X-CSRF-Token: ${CSRF_TOKEN}" \
            -X POST "${PANEL_INTERNAL}${path}" "$@"
    else
        curl -s -b "$COOKIE_JAR" \
            -X POST "${PANEL_INTERNAL}${path}" "$@"
    fi
}

api_get() {
    if [ -n "$API_TOKEN" ]; then
        curl -s -H "Authorization: Bearer ${API_TOKEN}" "${PANEL_INTERNAL}$1"
    else
        curl -s -b "$COOKIE_JAR" "${PANEL_INTERNAL}$1"
    fi
}

existing_inbound_tags() {
    api_get "/panel/api/inbounds/list/slim" | jq -r '.obj[]?.tag // empty' 2>/dev/null
}

inbound_id_by_tag() {
    local tag="$1"
    api_get "/panel/api/inbounds/list/slim" | jq -r --arg t "$tag" '.obj[]? | select(.tag==$t) | .id' 2>/dev/null | head -n1
}

client_exists() {
    local email="$1" enc
    enc=$(jq -nr --arg e "$email" '$e|@uri')
    resp=$(api_get "/panel/api/clients/get/${enc}")
    ok=$(echo "$resp" | jq -r '.success // empty' 2>/dev/null)
    [ "$ok" = "true" ]
}

delete_inbound() {
    local tag="$1"
    local id
    id=$(inbound_id_by_tag "$tag")
    if [ -n "$id" ] && [ "$id" != "null" ]; then
        LOG "🗑️ Deleting inbound: ${tag} (ID: ${id})"
        resp=$(api_post "/panel/api/inbounds/del/$id" "{}")
        ok=$(echo "$resp" | jq -r '.success // empty' 2>/dev/null)
        if [ "$ok" = "true" ]; then
            LOG "✅ Inbound ${tag} deleted."
            return 0
        else
            LOG "❌ Failed to delete inbound ${tag}: $resp"
            return 1
        fi
    fi
    return 0
}

delete_client() {
    local email="$1"
    if client_exists "$email"; then
        LOG "🗑️ Deleting client: ${email}"
        resp=$(api_post "/panel/api/clients/del/${email}" "{}")
        ok=$(echo "$resp" | jq -r '.success // empty' 2>/dev/null)
        if [ "$ok" = "true" ]; then
            LOG "✅ Client ${email} deleted."
            return 0
        else
            LOG "❌ Failed to delete client ${email}: $resp"
            return 1
        fi
    fi
    return 0
}

# ---- Display names (shown as config names in links / subscription) -------------
# small_caps "united kingdom" -> ᴜɴɪᴛᴇᴅ ᴋɪɴɢᴅᴏᴍ
small_caps() {
    jq -nr --arg s "$1" '
        "abcdefghijklmnopqrstuvwxyz" as $a
        | ("ᴀʙᴄᴅᴇꜰɢʜɪᴊᴋʟᴍɴᴏᴘǫʀꜱᴛᴜᴠᴡxʏᴢ" | split("")) as $b
        | ($s | ascii_downcase | split("") | map(. as $c | ($a | index($c)) as $i | if $i == null then $c else $b[$i] end) | join(""))'
}

# flag_emoji de -> 🇩🇪
flag_emoji() {
    jq -nr --arg c "$1" '$c | ascii_upcase | explode | map(. + 127397) | implode'
}

# display_name <tag> <label>  ->  "🇩🇪 ɢᴇʀᴍᴀɴʏ"  /  "🌐 ᴅɪʀᴇᴄᴛ"
display_name() {
    local tag="$1" label="$2" name icon
    name=$(small_caps "$label")
    if [ "$tag" = "$DIRECT_TAG" ]; then
        icon="🌐"
    else
        icon=$(flag_emoji "$tag")
    fi
    if [ -z "$name" ] || [ -z "$icon" ]; then
        printf '%s' "$label"      # safe fallback: plain label
    else
        printf '%s %s' "$icon" "$name"
    fi
}

create_inbound() {
    local tag="$1" label="$2" port="$3" path="$4" protocol="$5"

    local settings streamSettings sniffing
    settings=$(jq -n '{clients: [], decryption: "none", fallbacks: []}')
    # External Proxy: make panel-generated links/subscriptions use the public domain on 443 with TLS
    local ext_dest=""
    case "$DOMAIN" in localhost*|"") ;; *) ext_dest="$DOMAIN" ;; esac
    streamSettings=$(jq -n --arg path "$path" --arg dom "$ext_dest" '
        {network: "ws", security: "none", wsSettings: {path: $path, headers: {}}}
        + (if $dom != "" then {externalProxy: [{forceTls: "tls", dest: $dom, port: 443, remark: ""}]} else {} end)
        | if $dom != "" then .wsSettings.host = $dom else . end')
    sniffing='{"enabled":true,"destOverride":["http","tls"],"metadataOnly":false,"routeOnly":false}'

    local body
    body=$(jq -n \
        --arg remark "$(display_name "$tag" "$label")" \
        --arg tag "$tag" \
        --argjson port "$port" \
        --argjson settings "$settings" \
        --argjson streamSettings "$streamSettings" \
        --argjson sniffing "$sniffing" \
        --arg protocol "$protocol" '{
            up: 0, down: 0, total: 0, remark: $remark, enable: true, expiryTime: 0,
            listen: "0.0.0.0", port: $port, protocol: $protocol,
            settings: $settings, streamSettings: $streamSettings, sniffing: $sniffing, tag: $tag
        }')

    resp=$(api_post "/panel/api/inbounds/add" "$body")
    ok=$(echo "$resp" | jq -r '.success // empty' 2>/dev/null)
    if [ "$ok" = "true" ]; then
        LOG "✅ Inbound created: ${label} (port ${port}, path ${path})"
        return 0
    else
        LOG "❌ Inbound for ${label} failed: $resp"
        return 1
    fi
}

create_client() {
    local tag="$1" label="$2" inbound_id="$3"
    local email="${tag}-client"

    if client_exists "$email"; then
        LOG "Client '${email}' already exists, skipping."
        return 0
    fi

    local client_body body
    client_body=$(jq -n --arg email "$email" --arg sub "$SUB_TOKEN" '{email: $email, subId: $sub, totalGB: 0, expiryTime: 0, tgId: 0, limitIp: 0, enable: true}')
    body=$(jq -n --argjson client "$client_body" --argjson id "$inbound_id" '{client: $client, inboundIds: [$id]}')

    resp=$(api_post "/panel/api/clients/add" "$body")
    ok=$(echo "$resp" | jq -r '.success // empty' 2>/dev/null)
    if [ "$ok" = "true" ]; then
        LOG "✅ Client created: ${email}"
        return 0
    else
        LOG "❌ Client creation for ${email} failed: $resp"
        return 1
    fi
}

log_client_link() {
    local email="$1" label="$2"
    resp=$(api_get "/panel/api/clients/links/${email}")
    ok=$(echo "$resp" | jq -r '.success // empty' 2>/dev/null)
    if [ "$ok" = "true" ]; then
        link=$(echo "$resp" | jq -r '.obj[0] // empty')
        if [ -n "$link" ] && [ "$link" != "null" ]; then
            LOG "🔗 ${label}: ${link}"
        else
            LOG "⚠️ ${label}: panel returned no link yet."
        fi
    fi
}

# Name shown after the country in every config. Change it with CLIENT_NAME in Railway.
SHARED_NAME="${CLIENT_NAME:-ᴠɪᴘ}"
SHARED_EMAIL="$SHARED_NAME"

# One client (one UUID, one subId) attached to the Direct inbound and every verified
# country inbound. The panel's subscription returns one link per attached inbound.
create_shared_client() {
    local ids_json="[]" id i code count
    if [ "$DIRECT_ENABLED" = "true" ]; then
        id=$(inbound_id_by_tag "$DIRECT_TAG")
        if [ -n "$id" ] && [ "$id" != "null" ]; then
            ids_json=$(printf '%s' "$ids_json" | jq -c --argjson i "$id" '. + [$i]')
        fi
    fi
    count=$(jq '.tor.countries | length' "$CONFIG_FILE")
    for i in $(seq 0 $((count - 1))); do
        code=$(jq -r ".tor.countries[$i].code" "$CONFIG_FILE")
        if is_location_verified "$code"; then
            id=$(inbound_id_by_tag "$code")
            if [ -n "$id" ] && [ "$id" != "null" ]; then
                ids_json=$(printf '%s' "$ids_json" | jq -c --argjson i "$id" '. + [$i]')
            fi
        fi
    done

    if [ "$ids_json" = "[]" ]; then
        LOG "❌ No inbounds found to attach the shared client to."
        return 1
    fi

    # Try the fancy name first; if the panel rejects it, fall back to a plain ASCII name.
    local candidate client_body body
    for candidate in "$SHARED_NAME" "all-locations"; do
        if client_exists "$candidate"; then
            LOG "Shared client '${candidate}' already exists, skipping."
            SHARED_EMAIL="$candidate"
            return 0
        fi
        client_body=$(jq -n --arg email "$candidate" --arg sub "$SUB_TOKEN" '{email: $email, subId: $sub, totalGB: 0, expiryTime: 0, tgId: 0, limitIp: 0, enable: true}')
        body=$(jq -n --argjson client "$client_body" --argjson ids "$ids_json" '{client: $client, inboundIds: $ids}')
        resp=$(api_post "/panel/api/clients/add" "$body")
        ok=$(echo "$resp" | jq -r '.success // empty' 2>/dev/null)
        if [ "$ok" = "true" ]; then
            SHARED_EMAIL="$candidate"
            LOG "✅ Shared client created: ${candidate} (inbound ids: ${ids_json})"
            return 0
        fi
        LOG "⚠️ Shared client '${candidate}' failed: ${resp:0:200}"
    done
    LOG "❌ Shared client creation failed."
    return 1
}

log_shared_links() {
    local enc
    enc=$(jq -nr --arg e "$SHARED_EMAIL" '$e|@uri')
    resp=$(api_get "/panel/api/clients/links/${enc}")
    ok=$(echo "$resp" | jq -r '.success // empty' 2>/dev/null)
    if [ "$ok" = "true" ]; then
        echo "$resp" | jq -r '.obj[]? // empty' | while read -r link; do
            [ -n "$link" ] && LOG "🔗 ${link}"
        done
    else
        LOG "⚠️ Could not fetch links for ${SHARED_EMAIL}: ${resp:0:200}"
    fi
}

# is_location_verified <code>
# Single source of truth for "did discovery succeed for this country?".
# Reads the status file written by start.sh's verify_tor_exit()/write_status_json().
is_location_verified() {
    local code="$1"
    local status_file="/var/www/tor-status/${code}.json"
    [ -f "$status_file" ] || return 1
    [ "$(jq -r '.verified // false' "$status_file" 2>/dev/null)" = "true" ]
}

get_failed_locations() {
    local failed=""
    local count
    count=$(jq '.tor.countries | length' "$CONFIG_FILE")
    for i in $(seq 0 $((count - 1))); do
        local code
        code=$(jq -r ".tor.countries[$i].code" "$CONFIG_FILE")
        is_location_verified "$code" || failed="$failed $code"
    done
    echo "$failed"
}


setup_outbounds_and_routing() {
    LOG "Setting up SOCKS5 outbounds and routing rules..."

    local verified_locations=""
    local count
    count=$(jq '.tor.countries | length' "$CONFIG_FILE")
    for i in $(seq 0 $((count - 1))); do
        local code
        code=$(jq -r ".tor.countries[$i].code" "$CONFIG_FILE")
        is_location_verified "$code" && verified_locations="$verified_locations $code"
    done
    LOG "✅ Verified locations: ${verified_locations:-none}"

    local tpl_resp obj_type current_json
    tpl_resp=$(api_post "/panel/api/xray/" "{}")

    local top_ok
    top_ok=$(echo "$tpl_resp" | jq -e '.obj' >/dev/null 2>&1; echo $?)
    if [ "$top_ok" != "0" ]; then
        LOG "❌ Could not fetch Xray config template. Raw: ${tpl_resp:0:200}"
        return 1
    fi

    obj_type=$(echo "$tpl_resp" | jq -r '.obj | type' 2>/dev/null)

    if [ "$obj_type" = "object" ]; then
        current_json=$(echo "$tpl_resp" | jq -c '.obj')
    elif [ "$obj_type" = "string" ]; then
        current_json=$(echo "$tpl_resp" | jq -r '.obj')
    else
        LOG "❌ Unexpected .obj type '${obj_type}' from /panel/api/xray/."
        return 1
    fi

    if ! echo "$current_json" | jq -e . >/dev/null 2>&1; then
        LOG "❌ xraySetting wasn't valid JSON. Raw: ${current_json:0:200}"
        return 1
    fi

    new_config="$current_json"


    jq_transform() {
        local desc="$1" filter="$2"; shift 2
        local result
        result=$(printf '%s' "$new_config" | jq "$@" "$filter" 2>>/var/log/panel-bootstrap.log)
        if [ $? -ne 0 ] || [ -z "$result" ] || ! printf '%s' "$result" | jq -e . >/dev/null 2>&1; then
            LOG "❌ jq transform failed (${desc}) — aborting outbound/routing update to avoid corrupting config"
            return 1
        fi
        new_config="$result"
        return 0
    }


    for i in $(seq 0 $((count - 1))); do
        local code
        code=$(jq -r ".tor.countries[$i].code" "$CONFIG_FILE")
        if ! is_location_verified "$code"; then
            LOG "🗑️ Removing outbound/routing for failed location: ${code}"
            jq_transform "remove outbound ${code}" \
                '.outbounds = [.outbounds[]? | select(.tag != $t)]' --arg t "$code" || return 1
            jq_transform "remove routing rule ${code}" \
                '.routing.rules = [.routing.rules[]? | select(.inboundTag == null or (.inboundTag | index($t)) == null)]' --arg t "$code" || return 1
        fi
    done

    # ---- Add outbound/routing for every VERIFIED country -----------------------
    for i in $(seq 0 $((count - 1))); do
        local code
        code=$(jq -r ".tor.countries[$i].code" "$CONFIG_FILE")
        if is_location_verified "$code"; then
            local tor_port outbound_tag
            tor_port=$(jq -r ".tor.countries[$i].port" "$CONFIG_FILE")
            outbound_tag="$code"   # bare country code — no "tor-" prefix, no "Tor" label

            local already
            already=$(printf '%s' "$new_config" | jq --arg t "$outbound_tag" '[.outbounds[]? | select(.tag==$t)] | length')
            if [ "$already" = "0" ]; then
                LOG "Adding outbound: ${outbound_tag} -> 127.0.0.1:${tor_port}"
                jq_transform "add outbound ${outbound_tag}" '
                    .outbounds += [{
                        tag: $t,
                        protocol: "socks",
                        settings: { servers: [{ address: "127.0.0.1", port: $p, users: [] }] },
                        streamSettings: { sockopt: { tcpFastOpen: true, tcpKeepAlive: true } }
                    }]' --arg t "$outbound_tag" --argjson p "$tor_port" || return 1
            fi

            local rule_exists
            rule_exists=$(printf '%s' "$new_config" | jq --arg t "$code" '
                [.routing.rules[]? | select(.inboundTag != null and (.inboundTag | index($t)) != null)] | length')
            if [ "$rule_exists" = "0" ]; then
                LOG "Adding routing rule: ${code} -> ${outbound_tag}"
                jq_transform "add routing rule ${code}" '
                    .routing.rules = ((.routing.rules // []) + [{
                        type: "field",
                        enabled: true,
                        inboundTag: [$t],
                        outboundTag: $ot
                    }])' --arg t "$code" --arg ot "$outbound_tag" || return 1
            fi
        fi
    done

    # ---- Direct (non-Tor) outbound — always present -----------------------------
    DIRECT_OUTBOUND_TAG="direct-outbound"
    already_direct=$(printf '%s' "$new_config" | jq --arg t "$DIRECT_OUTBOUND_TAG" '[.outbounds[]? | select(.tag==$t)] | length')
    if [ "$already_direct" = "0" ]; then
        LOG "Adding direct (non-Tor) outbound: ${DIRECT_OUTBOUND_TAG}"
        jq_transform "add direct outbound" '
            .outbounds += [{
                tag: $t,
                protocol: "freedom",
                settings: {}
            }]' --arg t "$DIRECT_OUTBOUND_TAG" || return 1
    fi

    DIRECT_INBOUND_TAG="direct-inbound"
    direct_rule_exists=$(printf '%s' "$new_config" | jq --arg t "$DIRECT_INBOUND_TAG" '
        [.routing.rules[]? | select(.inboundTag != null and (.inboundTag | index($t)) != null)] | length')
    if [ "$direct_rule_exists" = "0" ]; then
        LOG "Adding routing rule: ${DIRECT_INBOUND_TAG} -> ${DIRECT_OUTBOUND_TAG}"
        jq_transform "add direct routing rule" '
            .routing.rules = ((.routing.rules // []) + [{
                type: "field",
                enabled: true,
                inboundTag: [$t],
                outboundTag: $ot
            }])' --arg t "$DIRECT_INBOUND_TAG" --arg ot "$DIRECT_OUTBOUND_TAG" || return 1
    fi

    if [ "$new_config" != "$current_json" ]; then
        local tmp_config
        tmp_config=$(mktemp /tmp/xray-setting.XXXXXX.json)
        printf '%s' "$new_config" > "$tmp_config"

        resp=$(api_post_form "/panel/api/xray/update" --data-urlencode "xraySetting@${tmp_config}")
        rm -f "$tmp_config"

        ok=$(echo "$resp" | jq -r '.success // empty' 2>/dev/null)
        if [ "$ok" = "true" ]; then
            LOG "✅ Outbounds + routing saved successfully."
            LOG "Restarting Xray via x-ui CLI..."
            if ! $XUI_BIN restart; then
                LOG "⚠️ x-ui restart command failed, trying stop/start..."
                $XUI_BIN stop
                sleep 5
                $XUI_BIN start
            fi
            sleep 8
            return 0
        else
            LOG "❌ Failed to save outbounds/routing. Response: $resp"
            return 1
        fi
    fi
    LOG "Outbounds + routing already up to date. Skipping restart."
    return 0
}

LOG "============================================================"
LOG "Panel bootstrap starting..."
wait_for_panel || exit 0
login || exit 0

existing=$(existing_inbound_tags)
LOG "Existing inbound tags: ${existing:-none}"

# ---- Direct (non-Tor) inbound -------------------------------------------------
if [ "$DIRECT_ENABLED" = "true" ]; then
    if ! echo "$existing" | grep -qx "$DIRECT_TAG"; then
        LOG "Creating Direct (Non-Tor) inbound on port ${DIRECT_PORT} (internal only)..."
        create_inbound "$DIRECT_TAG" "Direct" "$DIRECT_PORT" "$DIRECT_PATH" "vless"
    else
        LOG "Direct inbound already exists."
    fi
fi

FAILED_LOCATIONS=$(get_failed_locations)
LOG "Failed locations (will not be created / will be removed): ${FAILED_LOCATIONS:-none}"

for CODE in $FAILED_LOCATIONS; do
    if echo "$existing" | grep -qx "$CODE"; then
        LOG "🗑️ Tearing down failed location: ${CODE}"
        delete_inbound "$CODE"
        delete_client "${CODE}-client"
    fi
done

COUNTRY_COUNT=$(jq '.tor.countries | length' "$CONFIG_FILE")
for i in $(seq 0 $((COUNTRY_COUNT - 1))); do
    CODE=$(jq -r ".tor.countries[$i].code" "$CONFIG_FILE")
    LABEL=$(jq -r ".tor.countries[$i].label" "$CONFIG_FILE")
    PORT=$(jq -r ".tor.countries[$i].inbound_port" "$CONFIG_FILE")
    PATH_WS=$(jq -r ".tor.countries[$i].path" "$CONFIG_FILE")

    if is_location_verified "$CODE"; then
        if ! echo "$existing" | grep -qx "$CODE"; then
            create_inbound "$CODE" "$LABEL" "$PORT" "$PATH_WS" "vless"
        fi
    else
        LOG "⚠️ Skipping ${CODE} — discovery did not verify this exit country"
    fi
done

sleep 2

# ---- One shared client attached to Direct + every VERIFIED country --------------
create_shared_client

# ---- Outbounds + routing -------------------------------------------------------
if ! setup_outbounds_and_routing; then
    LOG "⚠️ Outbound/routing cleanup did not complete successfully — check the log above."
    LOG "⚠️ Panel may still show stale outbounds for failed countries until the next run."
fi

LOG "============================================================"
LOG "Fetching panel-generated client links..."

log_shared_links

LOG "============================================================"
VERIFIED_COUNT=$(find /var/www/tor-status -maxdepth 1 -name "*.json" ! -name "all.json" ! -name "setup-progress.json" -exec jq -r '.verified // false' {} \; 2>/dev/null | grep -c "true" || echo "0")
LOG "✅ Panel bootstrap completed!"
LOG "✅ ${VERIFIED_COUNT}/${COUNTRY_COUNT} country exits verified and active"
LOG "🌐 Direct (Non-Tor) available at path ${DIRECT_PATH} (behind nginx, single public port)"
LOG "🔒 Verified countries are available at their configured /inN paths"
LOG "📥 Subscription URL: https://${DOMAIN}/sub/${SUB_TOKEN}"
LOG "📊 Panel: https://${DOMAIN}/managepanel/"
LOG "============================================================"
