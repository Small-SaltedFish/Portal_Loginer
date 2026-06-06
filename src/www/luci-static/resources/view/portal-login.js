'use strict';
'require rpc';
'require view';
'require poll';

var callStatus = rpc.declare({ object:'portal-login', method:'get_status', expect:{} });
var callLogs   = rpc.declare({ object:'portal-login', method:'get_logs', params:['lines'], expect:{} });
var callConfig = rpc.declare({ object:'portal-login', method:'get_config', expect:{} });
var callSet    = rpc.declare({ object:'portal-login', method:'set_config',
    params:['user','pass','key','probe_url','check_interval','retry_interval',
            'relogin_hour','log_max','debug','enabled'], expect:{} });
var callAct    = rpc.declare({ object:'portal-login', method:'do_action', params:['action'], expect:{} });

/* ─── CSS ───────────────────────────────────────────────────────────────── */
var CSS = `
:root {
  --pl-bg:#f0f2f5; --pl-card:#fff; --pl-border:#e5e7eb;
  --pl-text:#1f2937; --pl-sub:#6b7280; --pl-label:#374151;
  --pl-in-bg:#fff; --pl-in-bd:#d1d5db;
  --pl-hd:#f9fafb; --pl-row:#f3f4f6;
  --pl-sh:0 1px 3px rgba(0,0,0,.07),0 1px 2px rgba(0,0,0,.04);
  --pl-p:#4f6ef7; --pl-p2:#3b54d4;
  --pl-ok-bg:#dcfce7; --pl-ok-tx:#15803d;
  --pl-wn-bg:#fef9c3; --pl-wn-tx:#854d0e;
  --pl-er-bg:#fee2e2; --pl-er-tx:#991b1b;
  --pl-of-bg:#f3f4f6; --pl-of-tx:#374151;
}
body.dark .pl,.pl.dark,[data-theme=dark] .pl {
  --pl-bg:#0f1117; --pl-card:#1c1f2e; --pl-border:#2d3148;
  --pl-text:#e2e8f0; --pl-sub:#94a3b8; --pl-label:#cbd5e1;
  --pl-in-bg:#252840; --pl-in-bd:#3d4270;
  --pl-hd:#161929; --pl-row:#1e2235;
  --pl-sh:0 1px 3px rgba(0,0,0,.4);
  --pl-ok-bg:#052e16; --pl-ok-tx:#4ade80;
  --pl-wn-bg:#451a03; --pl-wn-tx:#fcd34d;
  --pl-er-bg:#450a0a; --pl-er-tx:#f87171;
  --pl-of-bg:#1e2235; --pl-of-tx:#94a3b8;
}
@media(prefers-color-scheme:dark){
  .pl:not(.light) {
    --pl-bg:#0f1117; --pl-card:#1c1f2e; --pl-border:#2d3148;
    --pl-text:#e2e8f0; --pl-sub:#94a3b8; --pl-label:#cbd5e1;
    --pl-in-bg:#252840; --pl-in-bd:#3d4270;
    --pl-hd:#161929; --pl-row:#1e2235;
    --pl-sh:0 1px 3px rgba(0,0,0,.4);
    --pl-ok-bg:#052e16; --pl-ok-tx:#4ade80;
    --pl-wn-bg:#451a03; --pl-wn-tx:#fcd34d;
    --pl-er-bg:#450a0a; --pl-er-tx:#f87171;
    --pl-of-bg:#1e2235; --pl-of-tx:#94a3b8;
  }
}
.pl { color:var(--pl-text); font:14px/1.5 system-ui,-apple-system,sans-serif; max-width:960px }
.pl-card { background:var(--pl-card); border:1px solid var(--pl-border); border-radius:12px; margin-bottom:16px; box-shadow:var(--pl-sh); overflow:hidden }
.pl-head { padding:11px 18px; background:var(--pl-hd); border-bottom:1px solid var(--pl-border); display:flex; justify-content:space-between; align-items:center }
.pl-head-l { font-weight:600; font-size:14px; display:flex; align-items:center; gap:7px }
.pl-body { padding:16px 18px }
/* 状态条 */
.pl-bar { display:flex; align-items:center; gap:10px; padding:10px 14px; background:var(--pl-row); border-radius:8px; border:1px solid var(--pl-border); margin-bottom:14px }
.pl-dot { width:8px; height:8px; border-radius:50%; flex-shrink:0 }
.pl-dot-ok  { background:#22c55e; box-shadow:0 0 0 0 rgba(34,197,94,.4); animation:plp 2s infinite }
.pl-dot-wn  { background:#f59e0b }
.pl-dot-er  { background:#ef4444 }
.pl-dot-off { background:#9ca3af }
@keyframes plp { 0%,100%{box-shadow:0 0 0 0 rgba(34,197,94,.4)} 50%{box-shadow:0 0 0 6px rgba(34,197,94,0)} }
.pl-bar-text { flex:1; font-size:13px }
.pl-bar-text b { font-weight:600 }
.pl-bar-ts { font-size:11px; color:var(--pl-sub) }
/* 徽章 */
.pl-badge { display:inline-flex; align-items:center; gap:3px; padding:3px 9px; border-radius:20px; font-size:11px; font-weight:600 }
.pl-ok  { background:var(--pl-ok-bg); color:var(--pl-ok-tx) }
.pl-wn  { background:var(--pl-wn-bg); color:var(--pl-wn-tx) }
.pl-er  { background:var(--pl-er-bg); color:var(--pl-er-tx) }
.pl-off { background:var(--pl-of-bg); color:var(--pl-of-tx) }
/* stat 网格 */
.pl-grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(145px,1fr)); gap:9px; margin-bottom:12px }
.pl-stat { background:var(--pl-row); border-radius:8px; padding:10px 12px }
.pl-sl { font-size:10px; text-transform:uppercase; letter-spacing:.5px; color:var(--pl-sub); margin-bottom:3px }
.pl-sv { font-size:15px; font-weight:700; word-break:break-all; line-height:1.3 }
.pl-sv-sm { font-size:12px !important; font-weight:500 !important }
/* meta */
.pl-meta { display:flex; flex-wrap:wrap; gap:12px; font-size:12px; color:var(--pl-sub) }
.pl-meta span { display:flex; align-items:center; gap:3px }
.pl-meta b { color:var(--pl-text); font-weight:500 }
/* 错误 */
.pl-err { color:#ef4444; font-size:12px; margin-top:8px; padding:7px 11px; background:var(--pl-er-bg); border-radius:6px; display:none }
/* 按钮 */
.pl-btns { display:flex; flex-wrap:wrap; gap:7px }
.pl-btn { padding:7px 16px; border:none; border-radius:7px; cursor:pointer; font-size:13px; font-weight:500; display:inline-flex; align-items:center; gap:5px; transition:opacity .15s,transform .1s; line-height:1; white-space:nowrap }
.pl-btn:hover { opacity:.84 } .pl-btn:active { transform:scale(.97) }
.pl-btn:disabled { opacity:.45; cursor:not-allowed }
.b-amber   { background:#d97706; color:#fff }
.b-green   { background:#16a34a; color:#fff }
.b-red     { background:#dc2626; color:#fff }
.b-blue    { background:var(--pl-p); color:#fff }
.b-ghost   { background:var(--pl-row); color:var(--pl-text); border:1px solid var(--pl-border) }
.b-sm      { padding:4px 10px; font-size:12px; border-radius:5px }
/* 表单 */
.pl-sec { font-size:11px; font-weight:600; color:var(--pl-sub); text-transform:uppercase; letter-spacing:.5px; margin:14px 0 8px }
.pl-fg2 { display:grid; grid-template-columns:1fr 1fr; gap:11px }
@media(max-width:560px){ .pl-fg2{ grid-template-columns:1fr } }
.pl-fg { display:flex; flex-direction:column; gap:3px }
.pl-fg label { font-size:12px; font-weight:500; color:var(--pl-label) }
.pl-fg .pl-hint { font-size:11px; color:var(--pl-sub) }
.pl-in { width:100%; padding:7px 10px; background:var(--pl-in-bg); border:1px solid var(--pl-in-bd); border-radius:7px; font-size:13px; color:var(--pl-text); box-sizing:border-box; outline:none; transition:border-color .15s }
.pl-in:focus { border-color:var(--pl-p); box-shadow:0 0 0 2px rgba(79,110,247,.12) }
/* 捕获结果 */
/* toggle */
.pl-tg { display:inline-flex; align-items:center; gap:8px; cursor:pointer; font-size:13px; color:var(--pl-text); user-select:none }
.pl-tg input { position:absolute; opacity:0; width:0; height:0 }
.pl-sw { position:relative; display:inline-block; width:36px; height:20px; background:var(--pl-in-bd); border-radius:10px; transition:background .2s; flex-shrink:0 }
.pl-sw::after { content:""; position:absolute; left:2px; top:2px; width:16px; height:16px; background:#fff; border-radius:50%; transition:transform .2s; box-shadow:0 1px 3px rgba(0,0,0,.2) }
.pl-tg input:checked ~ .pl-sw { background:var(--pl-p) }
.pl-tg input:checked ~ .pl-sw::after { transform:translateX(16px) }
.pl-div { height:1px; background:var(--pl-border); margin:13px 0 }
/* 日志 */
.pl-log-wrap { background:var(--pl-hd); border:1px solid var(--pl-border); border-radius:8px; overflow:hidden }
.pl-log-bar { display:flex; align-items:center; gap:7px; padding:7px 11px; border-bottom:1px solid var(--pl-border) }
.pl-log-bar select { padding:3px 6px; background:var(--pl-in-bg); border:1px solid var(--pl-in-bd); border-radius:5px; font-size:12px; color:var(--pl-text) }
.pl-log { font-family:"SFMono-Regular",Consolas,monospace; font-size:11.5px; padding:10px 12px; height:300px; overflow-y:auto; white-space:pre; overflow-x:auto; line-height:1.65 }
.l-i{color:#4ade80} .l-w{color:#fbbf24} .l-e{color:#f87171} .l-d{color:#93c5fd}
/* toast */
.pl-toast { position:fixed; bottom:22px; right:22px; padding:9px 17px; border-radius:8px; font-size:13px; color:#fff; font-weight:500; opacity:0; transition:opacity .22s,transform .22s; transform:translateY(6px); z-index:9999; pointer-events:none; box-shadow:0 4px 12px rgba(0,0,0,.2) }
.pl-toast.on { opacity:1; transform:translateY(0) }
`;

return view.extend({
    _n: 100,      // 日志行数
    _toast: null,
    _root:  null,
    _ttimer: null,
    _prevLog: '',
    _prevStatus: '',

    /* ── 工具 ── */
    $: function(id){ return document.getElementById('pl-'+id); },
    dark: function(){
        var b = document.body;
        return b.classList.contains('dark') ||
               b.getAttribute('data-theme')==='dark' ||
               (window.matchMedia && window.matchMedia('(prefers-color-scheme:dark)').matches);
    },
    syncDark: function(){
        if (!this._root) return;
        this.dark() ? this._root.classList.add('dark') : this._root.classList.remove('dark');
    },
    toast: function(msg, ok){
        var t = this._toast; if(!t) return;
        t.textContent = msg;
        t.style.background = ok===false ? '#dc2626' : '#16a34a';
        t.classList.add('on');
        clearTimeout(this._ttimer);
        this._ttimer = setTimeout(function(){ t.classList.remove('on'); }, 2800);
    },
    mk: function(tag, attrs, kids){
        var el = document.createElement(tag);
        if (attrs) Object.keys(attrs).forEach(function(k){
            if (k==='cls') el.className=attrs[k];
            else if (k==='html') el.innerHTML=attrs[k];
            else if (k==='txt') el.textContent=attrs[k];
            else if (k==='id') el.id='pl-'+attrs[k];
            else el.setAttribute(k, attrs[k]);
        });
        if (kids) kids.forEach(function(c){
            if (c==null) return;
            el.appendChild(typeof c==='string' ? document.createTextNode(c) : c);
        });
        return el;
    },
    btn: function(txt, cls, fn){
        var b = this.mk('button',{cls:'pl-btn '+cls, txt:txt});
        b.addEventListener('click', fn); return b;
    },
    inp: function(id, type, ph, extra){
        var a = {cls:'pl-in', id:id, type:type||'text'};
        if (ph) a.placeholder=ph;
        if (extra) Object.keys(extra).forEach(function(k){ a[k]=extra[k]; });
        return this.mk('input', a);
    },
    fg: function(lbl, el, hint){
        var self=this, kids=[self.mk('label',{txt:lbl}), el];
        if (hint) kids.push(self.mk('div',{cls:'pl-hint',txt:hint}));
        return self.mk('div',{cls:'pl-fg'},kids);
    },
    tog: function(id, lbl){
        var inp = this.mk('input',{type:'checkbox',id:id});
        var sw  = this.mk('span',{cls:'pl-sw'});
        return this.mk('label',{cls:'pl-tg'},[inp,sw,lbl]);
    },
    card: function(icon, title, extra, body){
        return this.mk('div',{cls:'pl-card'},[
            this.mk('div',{cls:'pl-head'},[
                this.mk('div',{cls:'pl-head-l'},[
                    this.mk('span',{txt:icon}),
                    this.mk('span',{txt:title})
                ]),
                extra||null
            ]),
            this.mk('div',{cls:'pl-body'},[body])
        ]);
    },
    stat: function(lbl, id, sm){
        return this.mk('div',{cls:'pl-stat'},[
            this.mk('div',{cls:'pl-sl',txt:lbl}),
            this.mk('div',{cls:'pl-sv'+(sm?' pl-sv-sm':''),id:id,txt:'—'})
        ]);
    },

    /* ── 操作 ── */
    act: function(action, msg){
        var self = this;
        /* 禁用所有按钮防重复 */
        var btns = self._root ? self._root.querySelectorAll('.pl-btn') : [];
        btns.forEach(function(b){ b.disabled=true; });
        callAct(action).then(function(r){
            self.toast(r.msg||msg||'完成', r.result==='ok');
            /* 立即连续刷新 */
            setTimeout(function(){ self.doStatus(); }, 500);
            setTimeout(function(){ self.doStatus(); }, 1800);
            setTimeout(function(){ self.doStatus(); }, 3500);
        }).catch(function(e){
            self.toast('失败: '+e.message, false);
        }).finally(function(){
            btns.forEach(function(b){ b.disabled=false; });
        });
    },

    /* 重启 = restart + relogin */
    actRestart: function(){
        var self = this;
        var btns = self._root ? self._root.querySelectorAll('.pl-btn') : [];
        btns.forEach(function(b){ b.disabled=true; });
        self.toast('重启中...', true);
        callAct('restart').then(function(){
            return new Promise(function(res){ setTimeout(res, 2000); });
        }).then(function(){
            return callAct('relogin');
        }).then(function(r){
            self.toast('重启完成，'+( r.msg||'重新登录中'), true);
            setTimeout(function(){ self.doStatus(); }, 600);
            setTimeout(function(){ self.doStatus(); }, 3000);
        }).catch(function(e){
            self.toast('重启失败: '+e.message, false);
        }).finally(function(){
            btns.forEach(function(b){ b.disabled=false; });
        });
    },

    /* ── 实时刷新 ── */
    doStatus: function(){
        var self = this;
        callStatus().then(function(s){
            if (!s) return;

            /* 判断真实状态 */
            var st = s.state;
            if (!s.running) st = 'STOPPED';

            /* 防抖：状态无变化不重绘 */
            var key = st+'|'+s.uptime+'|'+s.fail_count+'|'+s.last_check+'|'+s.error;
            if (key === self._prevStatus) return;
            self._prevStatus = key;

            /* dot + 文字 */
            var dotCls='pl-dot-off', bdgCls='pl-off', lbl='—', procTxt='';
            switch(st){
                case 'LOGGED_IN':
                    dotCls='pl-dot-ok'; bdgCls='pl-ok'; lbl='已登录 ✓'; break;
                case 'LOGGING_IN':
                    dotCls='pl-dot-wn'; bdgCls='pl-wn'; lbl='登录中...'; break;
                case 'FAILED':
                    dotCls='pl-dot-er'; bdgCls='pl-er'; lbl='登录失败'; break;
                case 'OFFLINE':
                    dotCls='pl-dot-off'; bdgCls='pl-off'; lbl='网络离线'; break;
                case 'STOPPED':
                    dotCls='pl-dot-off'; bdgCls='pl-off'; lbl='服务停止'; break;
                default:
                    lbl=st||'—';
            }
            procTxt = s.running
                ? '<span style="color:#22c55e;font-weight:500">守护进程运行中</span>'
                : '<span style="color:#ef4444">守护进程未运行</span>';

            var dot=self.$('dot'), bt=self.$('bar-text'), ts=self.$('ts');
            if (dot){ dot.className='pl-dot '+dotCls; }
            if (bt){ bt.innerHTML='<b>'+lbl+'</b> &nbsp;·&nbsp; '+procTxt; }
            if (ts){ ts.textContent=new Date().toLocaleTimeString(); }

            function sv(id,v){ var e=self.$(id); if(e) e.textContent=v||'—'; }
            sv('uptime',     s.uptime);
            sv('fail',       String(s.fail_count||0));
            sv('p-host',     s.p_host);
            sv('p-bras',     s.p_bras);
            sv('p-ip',       s.p_clientip);
            sv('p-vlan',     s.p_vlan);
            sv('last-login', s.last_login);
            sv('last-check', s.last_check);

            var ee=self.$('err');
            if (ee){ ee.textContent=s.error||''; ee.style.display=s.error?'block':'none'; }
        }).catch(function(){});
    },

    doLogs: function(){
        var self = this;
        callLogs(self._n).then(function(r){
            var raw = (r.lines||'').replace(/\\n/g,'\n').trimEnd();
            if (raw === self._prevLog) return;
            self._prevLog = raw;
            var box=self.$('log');
            if (!box) return;
            if (!raw){ box.innerHTML='<span style="color:var(--pl-sub)">暂无日志</span>'; return; }
            var atBottom = box.scrollHeight-box.scrollTop-box.clientHeight < 30;
            box.innerHTML = raw.split('\n').map(function(ln){
                var cls='';
                if (ln.indexOf('[INFO')>=0)  cls='l-i';
                else if (ln.indexOf('[WARN')>=0)  cls='l-w';
                else if (ln.indexOf('[ERROR')>=0) cls='l-e';
                else if (ln.indexOf('[DEBUG')>=0) cls='l-d';
                var s=ln.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
                return cls?'<span class="'+cls+'">'+s+'</span>':s;
            }).join('\n');
            if (atBottom) box.scrollTop=box.scrollHeight;
        }).catch(function(){});
    },

    loadCfg: function(){
        var self = this;
        callConfig().then(function(c){
            function sv(id,v){ var e=self.$(id); if(e) e.value=v||''; }
            sv('user',    c.user);
            sv('probe',   c.probe_url);
            sv('key',     c.key);
            sv('check',   c.check_interval);
            sv('retry',   c.retry_interval);
            sv('rh',      c.relogin_hour!==undefined?String(c.relogin_hour):'4');
            sv('logmax',  c.log_max||'500');
            /* 密码不回填，仅提示 */
            var ph=self.$('ph'); if(ph) ph.textContent=c.has_pass?'（已设置，留空不修改）':'（尚未设置）';
            /* toggles */
            function sc(id,v){ var e=self.$(id); if(e) e.checked=(v==='1'||v===1||v===true); }
            sc('autostart', c.enabled);
            sc('debug',     c.debug);
        }).catch(function(){});
    },

    saveCfg: function(){
        var self = this;
        function gv(id){ var e=self.$(id); return e?e.value:''; }
        function gc(id){ var e=self.$(id); return e&&e.checked?1:0; }
        var rh=parseInt(gv('rh')); if(isNaN(rh)) rh=4;
        var lm=parseInt(gv('logmax')); if(isNaN(lm)||lm<50) lm=200;
        callSet(
            gv('user'), gv('pass'),
            gv('key').length===16?gv('key'):'',
            gv('probe'),
            parseInt(gv('check'))||30,
            parseInt(gv('retry'))||10,
            rh, lm, gc('debug'), gc('autostart')
        ).then(function(r){
            self.toast(r.result==='ok'?'配置已保存':'保存失败', r.result==='ok');
            var pe=self.$('pass'); if(pe) pe.value='';
            self.loadCfg();
        }).catch(function(e){ self.toast('保存失败: '+e.message, false); });
    },

    /* ── 渲染 ── */
    render: function(){
        var self = this;

        /* 注入样式 */
        var st=document.createElement('style'); st.textContent=CSS;
        (document.head||document.body).appendChild(st);

        /* toast */
        var toast=self.mk('div',{cls:'pl-toast',id:'pl-toast'});
        document.body.appendChild(toast);
        self._toast=toast;

        /* root */
        var root=self.mk('div',{cls:'pl'});
        self._root=root;
        self.syncDark();

        /* 深色变化监听 */
        if (window.matchMedia)
            window.matchMedia('(prefers-color-scheme:dark)')
                .addEventListener('change',function(){ self.syncDark(); });
        if (window.MutationObserver)
            new MutationObserver(function(){ self.syncDark(); })
                .observe(document.body,{attributes:true,attributeFilter:['class','data-theme']});

        /* ── 1. 状态卡 ── */
        var bar=self.mk('div',{cls:'pl-bar'},[
            self.mk('div',{cls:'pl-dot pl-dot-off',id:'dot'}),
            self.mk('div',{cls:'pl-bar-text',id:'bar-text',html:'<b>—</b>'}),
            self.mk('div',{cls:'pl-bar-ts',id:'ts'})
        ]);
        var grid=self.mk('div',{cls:'pl-grid'},[
            self.stat('在线时长','uptime',false),
            self.stat('累计失败','fail',false),
            self.stat('Portal Host','p-host',true),
            self.stat('BRAS','p-bras',true),
            self.stat('分配 IP','p-ip',true),
            self.stat('VLAN','p-vlan',true)
        ]);
        var meta=self.mk('div',{cls:'pl-meta'},[
            self.mk('span',{},[self.mk('span',{txt:'🕐'}),' 上次登录 ',self.mk('b',{id:'last-login',txt:'—'})]),
            self.mk('span',{},[self.mk('span',{txt:'🔄'}),' 上次检查 ',self.mk('b',{id:'last-check',txt:'—'})])
        ]);
        var err=self.mk('div',{cls:'pl-err',id:'err'});
        root.appendChild(self.card('📡','连接状态',null,self.mk('div',{},[bar,grid,meta,err])));

        /* ── 2. 操作卡 ── */
        var ctrlBody=self.mk('div',{cls:'pl-btns'},[
            self.btn('🔄 立即登录',   'b-amber',function(){ self.act('relogin','重新登录中'); }),
            self.btn('▶ 启动',        'b-green', function(){ self.act('start','启动中'); }),
            self.btn('⏹ 停止',        'b-red',   function(){ self.act('stop','已停止'); }),
            self.btn('↺ 重启',         'b-blue',  function(){ self.actRestart(); })
        ]);
        /* 操作说明 */
        var hints=[
            '立即登录：强制执行一次登录（无论当前状态，先登出再重新认证）',
            '启动：启动守护进程，自动探测并保持在线',
            '停止：关闭守护进程，停止所有自动认证',
            '重启：重启守护进程并立即重新登录'
        ];
        var hintEl=self.mk('div',{style:'margin-top:10px;font-size:11px;color:var(--pl-sub);line-height:1.8'},
            hints.map(function(h){ return self.mk('div',{txt:'• '+h}); })
        );
        root.appendChild(self.card('⚙️','操作控制',null,self.mk('div',{},[ctrlBody,hintEl])));

        /* ── 3. 配置卡 ── */
        var phEl   = self.mk('div',{cls:'pl-hint',id:'ph'});
        var passEl = self.inp('pass','password','留空不修改');

        /* 探测 URL */
        var probeInp=self.inp('probe','text','http://connecttest.com/');

        var cfgBody=self.mk('div',{},[
            self.mk('div',{cls:'pl-sec',txt:'账号凭据'}),
            self.mk('div',{cls:'pl-fg2'},[
                self.fg('校园网账号', self.inp('user','text','[学号]@net')),
                self.mk('div',{cls:'pl-fg'},[self.mk('label',{txt:'密码'}),passEl,phEl])
            ]),
            self.mk('div',{cls:'pl-div'}),
            self.mk('div',{cls:'pl-sec',txt:'Portal 参数'}),
            self.mk('div',{cls:'pl-fg2'},[
                self.fg('探测 URL', probeInp,
                    '触发 302 重定向的纯 HTTP 地址，一般无需修改'),
                self.fg('AES 加密密钥（16位，留空不修改）',
                    self.inp('key','text','留空保持现有密钥',{maxlength:'16'}),
                    '默认 5a3b9f207411a8ed，程序会自动检测更新')
            ]),
            self.mk('div',{cls:'pl-div'}),
            self.mk('div',{cls:'pl-sec',txt:'定时策略'}),
            self.mk('div',{cls:'pl-fg2'},[
                self.fg('在线检测间隔（秒）',
                    self.inp('check','number','30',{min:'5',max:'600'}),
                    '建议 30~60 秒'),
                self.fg('失败重试间隔（秒）',
                    self.inp('retry','number','10',{min:'5',max:'300'}),
                    '登录失败后等待时间'),
                self.fg('每日重新登录时间（0~23，-1 禁用）',
                    self.inp('rh','number','4',{min:'-1',max:'23'}),
                    '如 4 = 每天凌晨 4:00 强制重认证，防会话过期'),
                self.fg('日志最大保留行数',
                    self.inp('logmax','number','500',{min:'50',max:'5000'}),
                    '超出后自动清除旧日志，建议 200~500')
            ]),
            self.mk('div',{cls:'pl-div'}),
            self.mk('div',{cls:'pl-sec',txt:'其他'}),
            self.mk('div',{style:'display:flex;flex-direction:column;gap:10px;margin-bottom:14px'},[
                self.tog('autostart','开机自动启动（路由器重启后自动运行守护进程并认证）'),
                self.tog('debug',   '调试日志（输出详细的 curl 请求和加密信息，日常无需开启）')
            ]),
            self.mk('div',{cls:'pl-btns'},[
                self.btn('💾 保存配置','b-blue', function(){ self.saveCfg(); }),
                self.btn('↺ 重置',     'b-ghost',function(){ self.loadCfg(); })
            ])
        ]);
        root.appendChild(self.card('📋','配置',null,cfgBody));

        /* ── 4. 日志卡 ── */
        var lnSel=document.createElement('select');
        [[50,'50行'],[100,'100行'],[200,'200行'],[500,'500行']].forEach(function(o){
            var op=document.createElement('option');
            op.value=String(o[0]); op.textContent=o[1];
            if(o[0]===100) op.selected=true;
            lnSel.appendChild(op);
        });
        lnSel.addEventListener('change',function(){ self._n=parseInt(lnSel.value); self._prevLog=''; self.doLogs(); });

        var logEl=self.mk('div',{cls:'pl-log',id:'log',txt:'加载中...'});

        var logBar=self.mk('div',{cls:'pl-log-bar'},[
            lnSel,
            self.btn('刷新','b-ghost b-sm',function(){ self._prevLog=''; self.doLogs(); }),
            self.btn('清空','b-red b-sm',function(){
                if(!confirm('确认清空所有日志？')) return;
                callAct('logs_clear').then(function(){
                    self._prevLog=''; self.toast('已清空',true); self.doLogs();
                });
            }),
            self.mk('span',{style:'flex:1'}),
            self.mk('span',{style:'font-size:11px;color:var(--pl-sub)',txt:'每 2 秒自动刷新'})
        ]);
        root.appendChild(self.card('📄','运行日志',null,
            self.mk('div',{cls:'pl-log-wrap'},[logBar,logEl])
        ));

        /* ── 初始化 & 轮询 ── */
        setTimeout(function(){ self.doStatus(); self.doLogs(); self.loadCfg(); }, 80);
        poll.add(function(){ self.doStatus(); }, 2);
        poll.add(function(){ self.doLogs();   }, 2);

        return root;
    },
    handleSaveSuccess: function(){},
    handleSaveError:   function(){}
});
