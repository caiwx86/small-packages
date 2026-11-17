'use strict';
'require view';
'require fs';
'require uci';
'require ui';

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

function getOpt(name, dflt) {
	var v = uci.get_first('netdata', 'netdata', name);
	return (v == null || v === '') ? dflt : v;
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

	if (window.location.protocol === 'https:')
		return null;

	return 'http://' + formatHost() + ':' + port + '/';
}

function directUrl(port) {
	return 'http://' + formatHost() + ':' + port + '/';
}

function isHttps() {
	return window.location.protocol === 'https:';
}

function note(text, kind) {
	var cls = 'nd-note';

	if (kind)
		cls += ' ' + kind;

	return E('div', { 'class': cls }, text);
}

function actionButton(label, icon, fn, cls, title) {
	return E('button', {
		'class': 'nd-btn' + (cls ? ' ' + cls : ''),
		'title': title || label,
		'click': fn
	}, [ icon ? E('span', { 'aria-hidden': 'true' }, icon) : '', label ]);
}

return view.extend({
	status: null,
	_url: null,
	_sig: null,
	_root: null,
	_timer: null,

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

		var known = (typeof st.running !== 'undefined');
		var running = known && st.running === '1';
		var port = st.port || getOpt('port', '19999');
		var url = (port === '0') ? null : buildUrl(st, port);

		this._url = url;
		this._sig = (running ? '1' : '0') + '|' + (st.ssl || '0') + '|' + port;

		var httpsNote = null;

		if (running && st.ssl === '1' && st.tls !== '1')
			httpsNote = note(_('检测到 HTTPS 配置，但当前 Netdata 构建可能不支持 TLS。'), 'error');

		var actions = [];

		if (running && url) {
			actions.push(E('a', {
				'class': 'nd-btn primary',
				'href': url,
				'target': '_blank',
				'rel': 'noopener'
			}, [ E('span', { 'aria-hidden': 'true' }, '↗'), _('打开仪表板') ]));

			actions.push(actionButton(_('刷新'), '↻', ui.createHandlerFn(this, 'reloadFrame')));
			actions.push(actionButton(_('全屏'), '⛶', ui.createHandlerFn(this, 'toggleFullscreen')));
			actions.push(actionButton(_('重启'), '⟳', ui.createHandlerFn(this, 'restartNetdata')));
			actions.push(actionButton(_('停止'), '■', ui.createHandlerFn(this, 'stopNetdata'), 'danger'));
		}
		else if (running && !url) {
			actions.push(actionButton(_('启用 HTTPS'), '🔒', ui.createHandlerFn(this, 'enableHttps'), 'primary'));
			actions.push(E('a', {
				'class': 'nd-btn',
				'href': directUrl(port),
				'target': '_blank',
				'rel': 'noopener'
			}, [ E('span', { 'aria-hidden': 'true' }, '↗'), _('新窗口打开') ]));
			actions.push(actionButton(_('重启'), '⟳', ui.createHandlerFn(this, 'restartNetdata')));
			actions.push(actionButton(_('停止'), '■', ui.createHandlerFn(this, 'stopNetdata'), 'danger'));
		}
		else if (known) {
			actions.push(actionButton(_('启动 Netdata'), '▶', ui.createHandlerFn(this, 'startNetdata'), 'primary'));
		}
		else {
			actions.push(actionButton(_('重试'), '↻', ui.createHandlerFn(this, 'reloadPage')));
		}

		actions.push(E('a', {
			'class': 'nd-btn',
			'href': L.url('admin/status/netdata/config')
		}, [ E('span', { 'aria-hidden': 'true' }, '⚙'), _('设置') ]));

		var pill = E('span', {
			'id': 'nd-pill',
			'class': 'nd-pill ' + (running ? 'running' : 'stopped')
		}, [
			E('span', { 'class': 'nd-dot' }),
			E('span', { 'id': 'nd-pill-text' }, running ? _('运行中') : (known ? _('已停止') : _('未知')))
		]);

		var meta = E('div', { 'class': 'nd-meta' }, [
			chip(_('端口'), port, 'nd-chip-port'),
			chip(_('PID'), running ? (st.pid || '-') : '-', 'nd-chip-pid'),
			chip(_('版本'), st.version || '-', 'nd-chip-version'),
			chip(_('连接'), st.ssl === '1' ? 'HTTPS' : 'HTTP', 'nd-chip-tls'),
			chip(_('开机自启'), st.enabled === '1' ? _('是') : _('否'), 'nd-chip-enabled')
		]);

		var hero = E('div', { 'class': 'nd-hero' }, [
			E('div', { 'class': 'nd-head' }, [
				E('div', {}, [
					E('div', { 'class': 'nd-title' }, [
						E('span', { 'class': 'nd-logo' }, 'N'),
						E('span', {}, 'Netdata'),
						pill
					]),
					E('p', { 'class': 'nd-sub' }, _('实时性能监控 · 数据每秒更新'))
				]),
				E('div', { 'class': 'nd-actions' }, actions)
			]),
			meta
		]);

		var body;

		if (running && url) {
			body = E('div', { 'class': 'nd-body' }, [
				E('div', {
					'class': 'nd-frame-wrap',
					'id': 'nd-frame-wrap'
				}, [
					E('iframe', {
						'id': 'nd-frame',
						'class': 'nd-frame',
						'title': 'Netdata',
						'src': url,
						'style': 'height:70vh; min-height:420px',
						'loading': 'eager',
						'referrerpolicy': 'same-origin'
					}),
					E('div', { 'id': 'nd-loading', 'class': 'nd-loading' }, [
						E('span', { 'class': 'nd-spinner' }),
						_('正在加载 Netdata 仪表板…')
					])
				])
			]);

			setTimeout(function() {
				var iframe = document.getElementById('nd-frame');
				var loading = document.getElementById('nd-loading');

				if (iframe) {
					iframe.addEventListener('load', function() {
						if (loading)
							loading.style.display = 'none';
						fitFrame(iframe);
					});
					fitFrame(iframe);
				}
			}, 30);

			window.addEventListener('resize', function() {
				var iframe = document.getElementById('nd-frame');
				if (iframe)
					fitFrame(iframe);
			});
		}
		else {
			body = emptyState(this, st, known, running, url, port);
		}

		var root = E('div', { 'class': 'nd' }, [
			E('link', {
				'rel': 'stylesheet',
				'href': L.resource('netdata/ui.css')
			}),
			hero,
			httpsNote,
			body
		]);

		this._root = root;

		if (this._timer)
			clearInterval(this._timer);

		this._timer = setInterval(function() {
			if (!view._root || !document.body.contains(view._root)) {
				clearInterval(view._timer);
				view._timer = null;
				return;
			}
			view.refresh();
		}, 10000);

		return root;
	},

	reloadPage: function() {
		window.location.reload();
	},

	refresh: function() {
		var view = this;

		return fetchStatus().then(function(st) {
			var running = st.running === '1';
			var port = st.port || getOpt('port', '19999');
			var sig = (running ? '1' : '0') + '|' + (st.ssl || '0') + '|' + port;

			if (sig !== view._sig && view._root && document.body.contains(view._root)) {
				window.location.reload();
				return;
			}

			view.status = st;
			updateStatusDom(st, running);
		});
	},

	startNetdata: function() {
		return fs.exec(CTL, [ 'start' ]).then(function(res) {
			var msg = firstLine(res.stdout) || firstLine(res.stderr) || _('完成。');
			ui.addNotification(null, E('p', msg), res.code === 0 ? 'info' : 'error');

			if (res.code === 0)
				setTimeout(function() { window.location.reload(); }, 700);
		}).catch(function(e) {
			ui.addNotification(null, E('p', e.message), 'error');
		});
	},

	stopNetdata: function() {
		return fs.exec(CTL, [ 'stop' ]).then(function(res) {
			var msg = firstLine(res.stdout) || firstLine(res.stderr) || _('完成。');
			ui.addNotification(null, E('p', msg), res.code === 0 ? 'info' : 'error');

			if (res.code === 0)
				setTimeout(function() { window.location.reload(); }, 300);
		}).catch(function(e) {
			ui.addNotification(null, E('p', e.message), 'error');
		});
	},

	restartNetdata: function() {
		var view = this;

		return fs.exec(CTL, [ 'restart' ]).then(function(res) {
			var msg = firstLine(res.stdout) || firstLine(res.stderr) || _('完成。');
			ui.addNotification(null, E('p', msg), res.code === 0 ? 'info' : 'error');

			if (res.code === 0 && view._url) {
				setTimeout(function() {
					var iframe = document.getElementById('nd-frame');
					var loading = document.getElementById('nd-loading');

					if (iframe) {
						if (loading)
							loading.style.display = '';
						iframe.src = view._url + (view._url.indexOf('?') >= 0 ? '&' : '?') + '_=' + Date.now();
					}
				}, 600);
			}
		}).catch(function(e) {
			ui.addNotification(null, E('p', e.message), 'error');
		});
	},

	enableHttps: function() {
		return fs.exec(CTL, [ 'ensure', 'https' ]).then(function(res) {
			var st = parseStatus(res.stdout);
			var msg = st.ssl === '1' ? _('HTTPS 已启用，正在重新加载…') : _('无法启用 HTTPS，请检查 netdata-ssl 与证书。');
			ui.addNotification(null, E('p', msg), st.ssl === '1' ? 'info' : 'error');

			if (st.ssl === '1')
				setTimeout(function() { window.location.reload(); }, 900);
		}).catch(function(e) {
			ui.addNotification(null, E('p', e.message), 'error');
		});
	},

	reloadFrame: function() {
		var iframe = document.getElementById('nd-frame');
		var loading = document.getElementById('nd-loading');

		if (iframe && this._url) {
			if (loading)
				loading.style.display = '';
			iframe.src = this._url + (this._url.indexOf('?') >= 0 ? '&' : '?') + '_=' + Date.now();
		}

		return this.refresh();
	},

	toggleFullscreen: function() {
		var wrap = document.getElementById('nd-frame-wrap');

		if (!wrap)
			return;

		if (document.fullscreenElement) {
			if (document.exitFullscreen)
				document.exitFullscreen();
		}
		else if (wrap.requestFullscreen) {
			wrap.requestFullscreen();
		}
	}
});

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

function updateStatusDom(st, running) {
	var pill = document.getElementById('nd-pill');
	var pillText = document.getElementById('nd-pill-text');

	if (pill)
		pill.className = 'nd-pill ' + (running ? 'running' : 'stopped');
	if (pillText)
		pillText.textContent = running ? _('运行中') : _('已停止');

	setChip('nd-chip-port', _('端口'), st.port || '-');
	setChip('nd-chip-pid', _('PID'), running ? (st.pid || '-') : '-');
	setChip('nd-chip-version', _('版本'), st.version || '-');
	setChip('nd-chip-tls', _('连接'), st.ssl === '1' ? 'HTTPS' : 'HTTP');
	setChip('nd-chip-enabled', _('开机自启'), st.enabled === '1' ? _('是') : _('否'));
}

function emptyState(view, st, known, running, url, port) {
	var icon = '⏸';
	var title = _('Netdata 未运行');
	var text = _('启动服务后即可在此查看实时性能监控。');
	var actions = [];

	if (!known) {
		icon = '⚠';
		title = _('无法获取服务状态');
		text = _('请确认 rpcd 正常运行，并已安装 netdata-ssl 软件包。');
		actions.push(actionButton(_('重试'), '↻', ui.createHandlerFn(view, 'reloadPage'), 'primary'));
	}
	else if (running && !url) {
		icon = '🔒';
		title = _('HTTPS 下无法内嵌仪表板');

		if (st.tls === '1') {
			text = _('点击“启用 HTTPS”将复用 LuCI 证书并重启 Netdata，随后仪表板会以加密连接显示在下方。');
			actions.push(actionButton(_('启用 HTTPS'), '🔒', ui.createHandlerFn(view, 'enableHttps'), 'primary'));
		}
		else {
			text = _('当前 Netdata 构建不支持原生 TLS。请安装 netdata-ssl，或改用 HTTP 访问 LuCI。');
		}

		actions.push(E('a', {
			'class': 'nd-btn',
			'href': directUrl(port),
			'target': '_blank',
			'rel': 'noopener'
		}, [ E('span', { 'aria-hidden': 'true' }, '↗'), _('新窗口打开') ]));
	}
	else {
		actions.push(actionButton(_('启动 Netdata'), '▶', ui.createHandlerFn(view, 'startNetdata'), 'primary'));
		actions.push(E('a', {
			'class': 'nd-btn',
			'href': L.url('admin/status/netdata/config')
		}, [ E('span', { 'aria-hidden': 'true' }, '⚙'), _('设置') ]));
	}

	return E('div', { 'class': 'nd-body' }, [
		E('div', { 'class': 'nd-empty' }, [
			E('div', { 'class': 'nd-empty-icon' }, icon),
			E('h4', {}, title),
			E('p', {}, text),
			E('div', { 'class': 'nd-actions' }, actions)
		])
	]);
}

function fitFrame(iframe) {
	if (!iframe)
		return;

	var wrap = document.getElementById('nd-frame-wrap');

	if (wrap && document.fullscreenElement)
		return;

	var rect = iframe.getBoundingClientRect();
	var height = Math.max(420, window.innerHeight - rect.top - 16);

	iframe.style.height = height + 'px';
}

document.addEventListener('fullscreenchange', function() {
	var iframe = document.getElementById('nd-frame');
	if (iframe)
		setTimeout(function() { fitFrame(iframe); }, 50);
});
