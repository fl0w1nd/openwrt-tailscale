'use strict';
'require view';
'require rpc';
'require ui';

var _ = function(s) { return s; };

var callGetLogs = rpc.declare({
	object: 'luci-tailscale',
	method: 'get_logs',
	expect: { '': {} }
});

var callClearLog = rpc.declare({
	object: 'luci-tailscale',
	method: 'clear_log',
	params: ['log_type']
});

function renderLogSection(title, logType, content) {
	var preEl = E('pre', {
		'style': 'white-space:pre;overflow-x:auto;overflow-y:auto;max-height:400px;' +
			'background:#1e1e1e;color:#d4d4d4;padding:12px;border-radius:4px;font-size:13px;' +
			'font-family:monospace;margin:0'
	}, content || _('(empty)'));

	var section = E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, title),
		E('div', { 'style': 'margin-bottom:8px;display:flex;gap:8px' }, [
			E('button', {
				'class': 'cbi-button cbi-button-action',
				'data-log-type': logType,
				'click': function() {
					var btn = this;
					btn.disabled = true;
					btn.classList.add('spinning');

					callGetLogs().then(function(result) {
						preEl.textContent = (result && result[logType]) || _('(empty)');
					}).catch(function(err) {
						ui.addNotification(null, E('p', {}, 'Failed to refresh log: ' + err.message), 'danger');
					}).finally(function() {
						btn.disabled = false;
						btn.classList.remove('spinning');
					});
				}
			}, _('Refresh')),
			E('button', {
				'class': 'cbi-button cbi-button-remove',
				'data-log-type': logType,
				'click': function() {
					var btn = this;
					btn.disabled = true;

					callClearLog(logType).then(function(result) {
						if (result && result.code === 0) {
							preEl.textContent = _('(empty)');
							ui.addNotification(null, E('p', {}, title + ' cleared.'), 'info');
						} else {
							ui.addNotification(null, E('p', {}, 'Failed to clear log.'), 'danger');
						}
					}).catch(function(err) {
						ui.addNotification(null, E('p', {}, 'Failed to clear log: ' + err.message), 'danger');
					}).finally(function() {
						btn.disabled = false;
					});
				}
			}, _('Clear'))
		]),
		preEl
	]);

	return section;
}

return view.extend({
	load: function() {
		return L.resolveDefault(callGetLogs(), {});
	},

	render: function(data) {
		var logs = data || {};

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Tailscale Logs')),
			E('div', { 'class': 'cbi-map-descr' }, _('View manager and Tailscale service logs for troubleshooting.')),
			renderLogSection(_('Manager Log'), 'manager', logs.manager),
			renderLogSection(_('Tailscale Log'), 'tailscale', logs.tailscale)
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
