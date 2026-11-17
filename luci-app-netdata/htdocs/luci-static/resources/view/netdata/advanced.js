'use strict';
'require view';
'require fs';
'require ui';

var CONF = '/etc/netdata/netdata.conf';
var CTL = '/usr/libexec/luci-app-netdata/netdata-ctl';

var isReadonlyView = (typeof L.hasViewPermission === 'function') && !L.hasViewPermission();

function firstLine(s) {
	return ((s || '').replace(/\r/g, '').split('\n')[0] || '').trim();
}

function normalize(value) {
	value = (value || '').replace(/\r\n/g, '\n');
	if (value.length && value.charAt(value.length - 1) !== '\n')
		value += '\n';
	return value;
}

return view.extend({
	handleSaveApply: null,
	handleReset: null,
	_original: '',

	load: function() {
		return fs.read(CONF).then(function(data) {
			return { data: data, error: null };
		}, function(err) {
			return { data: null, error: (err && err.message) ? err.message : String(err) };
		});
	},

	handleSave: function() {
		if (isReadonlyView)
			return;

		var ta = document.querySelector('textarea');
		if (!ta)
			return;

		var value = normalize(ta.value);

		if (value === this._original) {
			ui.addNotification(null, E('p', _('没有需要保存的更改。')), 'info');
			return;
		}

		return fs.write(CONF, value).then(function() {
			ta.value = value;
			ui.addNotification(null, E('p',
				_('配置已保存。文件变化后 Netdata 会自动重启。')), 'info');
		}).catch(function(e) {
			ui.addNotification(null, E('p',
				_('保存失败：%s').format(e.message)), 'error');
		});
	},

	render: function(res) {
		var link = E('link', {
			'rel': 'stylesheet',
			'href': L.resource('netdata/ui.css')
		});

		if (!res || res.error) {
			return E('div', { 'class': 'nd' }, [
				link,
				E('div', { 'class': 'nd-hero' }, [
					E('div', { 'class': 'nd-title' }, [
						E('span', { 'class': 'nd-logo' }, 'N'),
						E('span', {}, _('高级配置'))
					])
				]),
				E('div', { 'class': 'nd-note error' },
					_('无法读取 /etc/netdata/netdata.conf：%s').format(res ? res.error : '?'))
			]);
		}

		var value = normalize(res.data);
		this._original = value;

		var attrs = {
			'style': 'width:100%; min-height:58vh; padding:14px; border:0; border-radius:12px; background:rgba(127,127,127,.07); color:inherit; font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; font-size:12.5px; line-height:1.55; resize:vertical',
			'rows': 30,
			'spellcheck': 'false',
			'wrap': 'off'
		};

		if (isReadonlyView)
			attrs.disabled = '';

		return E('div', { 'class': 'nd' }, [
			link,
			E('div', { 'class': 'nd-hero' }, [
				E('div', { 'class': 'nd-head' }, [
					E('div', {}, [
						E('div', { 'class': 'nd-title' }, [
							E('span', { 'class': 'nd-logo' }, 'N'),
							E('span', {}, _('高级配置')),
							E('span', { 'class': 'nd-pill' }, 'netdata.conf')
						]),
						E('p', { 'class': 'nd-sub' }, _('仅建议高级用户修改。端口、监听地址与 HTTPS 由设置页管理。'))
					]),
					E('div', { 'class': 'nd-actions' }, [
						E('a', {
							'class': 'nd-btn',
							'href': L.url('admin/status/netdata/config')
						}, [ E('span', { 'aria-hidden': 'true' }, '←'), _('返回设置') ]),
						E('button', {
							'class': 'nd-btn',
							'click': ui.createHandlerFn(this, 'restart')
						}, [ E('span', { 'aria-hidden': 'true' }, '⟳'), _('重启 Netdata') ])
					])
				])
			]),
			E('div', { 'class': 'nd-note' },
				_('配置文件中的 [web] default port、ssl certificate、ssl key 由设置页写入；在此修改后，下次保存设置可能会被覆盖。')),
			E('div', { 'class': 'nd-body', 'style': 'padding:12px' }, [
				E('textarea', attrs, [ value ])
			])
		]);
	},

	restart: function() {
		return fs.exec(CTL, [ 'restart' ]).then(function(res) {
			var msg = firstLine(res.stdout) || firstLine(res.stderr) || _('完成。');
			ui.addNotification(null, E('p', msg), res.code === 0 ? 'info' : 'error');
		}).catch(function(e) {
			ui.addNotification(null, E('p', e.message), 'error');
		});
	}
});
