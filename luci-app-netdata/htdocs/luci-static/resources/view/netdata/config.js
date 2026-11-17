'use strict';
'require view';
'require fs';
'require uci';
'require ui';
'require form';

var CTL = '/usr/libexec/luci-app-netdata/netdata-ctl';

function firstLine(s) {
	return ((s || '').replace(/\r/g, '').split('\n')[0] || '').trim();
}

function parseStatus(out) {
	var st = {};

	(out || '').split(/\r?\n/).forEach(function(line) {
		var m = line.match(/^([a-z_]+)=(.*)$/);
		if (m)
			st[m[1]] = m[2];
	});

	return st;
}

function fetchStatus() {
	return L.resolveDefault(fs.exec(CTL, [ 'status' ]), {}).then(function(res) {
		return parseStatus(res && res.stdout ? res.stdout : '');
	});
}

function isHttps() {
	return window.location.protocol === 'https:';
}

function formatHost() {
	var host = window.location.hostname || '';

	if (host.indexOf(':') >= 0 && host.charAt(0) !== '[')
		host = '[' + host + ']';

	return host;
}

function buildUrl(st, port) {
	if (st.ssl === '1')
		return 'https://' + formatHost() + ':' + port + '/';

	if (isHttps())
		return null;

	return 'http://' + formatHost() + ':' + port + '/';
}

function chip(label, value, id) {
	return E('span', { 'class': 'nd-chip', 'id': id }, [
		label + ' ',
		E('b', {}, value)
	]);
}

function setChip(id, label, value) {
	var el = document.getElementById(id);

	if (!el)
		return;

	var b = el.querySelector('b');

	if (!b) {
		el.textContent = label + ' ' + value;
		return;
	}

	if (el.firstChild)
		el.firstChild.nodeValue = label + ' ';
	else
		el.insertBefore(document.createTextNode(label + ' '), b);

	b.textContent = value;
}

return view.extend({
	status: null,
	_url: null,

	load: function() {
		return Promise.all([
			uci.load('netdata'),
			fetchStatus()
		]).then(function(res) {
			var st = res[1] || {};

			if (!isHttps())
				return [ res[0], st ];

			return fs.exec(CTL, [ 'ensure', 'https' ]).then(function(r) {
				var extra = parseStatus(r.stdout);
				Object.keys(extra).forEach(function(k) { st[k] = extra[k]; });
				return [ res[0], st ];
			}, function() {
				return [ res[0], st ];
			});
		});
	},

	render: function(res) {
		var view = this;
		var st = res[1] || {};

		this.status = st;

		var running = st.running === '1';
		var port = st.port || uci.get_first('netdata', 'netdata', 'port') || '19999';
		var url = (port === '0') ? null : buildUrl(st, port);

		this._url = url;

		var actions = [];

		actions.push(E('a', {
			'id': 'nd-open',
			'class': 'nd-btn primary',
			'href': url || '#',
			'target': '_blank',
			'rel': 'noopener',
			'style': url ? '' : 'display:none'
		}, [ E('span', { 'aria-hidden': 'true' }, '↗'), _('打开仪表板') ]));

		actions.push(E('button', {
			'class': 'nd-btn',
			'title': _('刷新状态'),
			'click': ui.createHandlerFn(this, 'refreshStatus')
		}, [ E('span', { 'aria-hidden': 'true' }, '↻'), _('刷新') ]));

		var hero = E('div', { 'class': 'nd-hero' }, [
			E('div', { 'class': 'nd-head' }, [
				E('div', {}, [
					E('div', { 'class': 'nd-title' }, [
						E('span', { 'class': 'nd-logo' }, 'N'),
						E('span', {}, 'Netdata'),
						E('span', {
							'id': 'nd-pill',
							'class': 'nd-pill ' + (running ? 'running' : 'stopped')
						}, [
							E('span', { 'class': 'nd-dot' }),
							E('span', { 'id': 'nd-pill-text' }, running ? _('运行中') : _('已停止'))
						])
					]),
					E('p', { 'class': 'nd-sub' }, _('基础设置 · 保持简洁，其余参数在高级配置中调整'))
				]),
				E('div', { 'class': 'nd-actions' }, actions)
			]),
			E('div', { 'class': 'nd-meta' }, [
				chip(_('端口'), port, 'nd-chip-port'),
				chip(_('PID'), running ? (st.pid || '-') : '-', 'nd-chip-pid'),
				chip(_('版本'), st.version || '-', 'nd-chip-version'),
				chip(_('连接'), st.ssl === '1' ? 'HTTPS' : 'HTTP', 'nd-chip-tls'),
				chip(_('开机自启'), st.enabled === '1' ? _('是') : _('否'), 'nd-chip-enabled')
			])
		]);

		var m = new form.Map('netdata', _('Netdata 设置'),
			_('只保留最常用的选项。保存并应用后，端口、监听地址和 HTTPS 策略会立即生效。'));

		var s = m.section(form.TypedSection, 'netdata', _('基础设置'));
		s.anonymous = true;
		s.addremove = false;

		var o = s.option(form.Flag, 'enabled', _('启用 Netdata'));
		o.rmempty = false;
		o.default = '1';
		o.description = _('取消勾选并应用会停止服务；勾选并应用会启动服务并设置开机自启。');

		o = s.option(form.Value, 'port', _('服务端口'));
		o.datatype = 'port';
		o.placeholder = '19999';
		o.default = '19999';
		o.rmempty = false;
		o.description = _('HTTP 与 HTTPS 共用此端口。修改后保存并应用会自动重启 Netdata。');

		o = s.option(form.ListValue, 'bind', _('监听地址'));
		o.default = '*';
		o.rmempty = false;
		o.value('*', _('所有接口（局域网内可访问）'));
		o.value('127.0.0.1', _('仅本机（只能从路由器访问）'));

		var currentBind = uci.get_first('netdata', 'netdata', 'bind');
		if (currentBind && currentBind !== '*' && currentBind !== '127.0.0.1')
			o.value(currentBind, currentBind + ' ' + _('（当前自定义值）'));

		o.description = _('Netdata 本身的访问控制仍然生效；如需从外网访问，请另行配置防火墙。');

		var formEl = m.render();

		var tlsNote = E('div', { 'id': 'nd-tls-note' });
		updateTlsNote(tlsNote, st, this);

		var advanced = E('div', { 'class': 'nd-advanced' }, [
			E('span', {}, _('需要调整采集器、更新频率等参数？')),
			E('a', {
				'class': 'nd-btn',
				'href': L.url('admin/status/netdata/advanced')
			}, [ E('span', { 'aria-hidden': 'true' }, '⌘'), _('编辑 netdata.conf') ])
		]);

		return E('div', { 'class': 'nd nd-config' }, [
			E('link', {
				'rel': 'stylesheet',
				'href': L.resource('netdata/ui.css')
			}),
			hero,
			tlsNote,
			formEl,
			advanced
		]);
	},

	handleSaveApply: function(ev, mode) {
		var view = this;

		return this.super('handleSaveApply', [ ev, mode ]).then(function() {
			if (mode === '0')
				return;
			return view.applySettings();
		});
	},

	applySettings: function() {
		var view = this;
		var scheme = isHttps() ? 'https' : 'http';

		return fs.exec(CTL, [ 'apply', scheme ]).then(function(res) {
			var ok = res.code === 0;
			var msg = firstLine(res.stdout) || firstLine(res.stderr) ||
				(ok ? _('设置已应用。') : _('应用设置失败。'));

			ui.addNotification(null, E('p', msg), ok ? 'info' : 'error');

			return fetchStatus().then(function(st) {
				view.status = st;
				updateStatusDom(st);
				var note = document.getElementById('nd-tls-note');
				if (note)
					updateTlsNote(note, st, view);
			});
		}).catch(function(e) {
			ui.addNotification(null, E('p',
				_('应用设置失败：%s').format(e.message)), 'error');
		});
	},

	refreshStatus: function() {
		var view = this;

		return fetchStatus().then(function(st) {
			view.status = st;
			updateStatusDom(st);
			var note = document.getElementById('nd-tls-note');
			if (note)
				updateTlsNote(note, st, view);
			return st;
		});
	},

	enableHttps: function() {
		var view = this;

		return fs.exec(CTL, [ 'ensure', 'https' ]).then(function(res) {
			var st = parseStatus(res.stdout);
			ui.addNotification(null, E('p',
				st.ssl === '1' ? _('HTTPS 已启用。') : _('无法启用 HTTPS，请检查证书与 netdata-ssl。')),
				st.ssl === '1' ? 'info' : 'error');
			return view.refreshStatus();
		}).catch(function(e) {
			ui.addNotification(null, E('p', e.message), 'error');
		});
	}
});

function updateStatusDom(st) {
	var running = st.running === '1';
	var pill = document.getElementById('nd-pill');
	var pillText = document.getElementById('nd-pill-text');

	if (pill)
		pill.className = 'nd-pill ' + (running ? 'running' : 'stopped');
	if (pillText)
		pillText.textContent = running ? _('运行中') : _('已停止');

	var port = st.port || uci.get_first('netdata', 'netdata', 'port') || '19999';
	var url = buildUrl(st, port);
	var open = document.getElementById('nd-open');

	if (open) {
		open.href = url || '#';
		open.style.display = (url && running) ? '' : 'none';
	}

	setChip('nd-chip-port', _('端口'), st.port || '-');
	setChip('nd-chip-pid', _('PID'), running ? (st.pid || '-') : '-');
	setChip('nd-chip-version', _('版本'), st.version || '-');
	setChip('nd-chip-tls', _('连接'), st.ssl === '1' ? 'HTTPS' : 'HTTP');
	setChip('nd-chip-enabled', _('开机自启'), st.enabled === '1' ? _('是') : _('否'));
}

function updateTlsNote(el, st, view) {
	while (el.firstChild)
		el.removeChild(el.firstChild);

	if (typeof st.tls === 'undefined') {
		el.appendChild(E('div', { 'class': 'nd-note error' },
			_('无法获取 TLS 状态，请检查 rpcd 与 netdata-ssl 是否正常。')));
		return;
	}

	if (st.tls !== '1') {
		el.appendChild(E('div', { 'class': 'nd-note error' },
			_('当前 Netdata 构建不支持 TLS。请安装 netdata-ssl 软件包后再启用 HTTPS。')));
		return;
	}

	if (st.ssl === '1') {
		el.appendChild(E('div', { 'class': 'nd-note ok' }, [
			_('HTTPS 已启用，证书：'),
			E('b', {}, st.cert || _('未知'))
		]));
		return;
	}

	if (isHttps()) {
		el.appendChild(E('div', { 'class': 'nd-note' }, [
			E('p', { 'style': 'margin:0 0 8px' },
				_('当前页面使用 HTTPS，但 Netdata 尚未启用加密连接。启用时会自动复用 LuCI 证书并重启服务。')),
			E('button', {
				'class': 'nd-btn primary',
				'click': ui.createHandlerFn(view, 'enableHttps')
			}, [ E('span', { 'aria-hidden': 'true' }, '🔒'), _('启用 HTTPS') ])
		]));
		return;
	}

	el.appendChild(E('div', { 'class': 'nd-note' },
		_('当前通过 HTTP 访问。使用 HTTPS 打开 LuCI 时会自动启用加密连接。')));
}
