'use strict';
'require view';
'require form';
'require uci';

return view.extend({
	render: function() {
		var m, s, o;

		m = new form.Map('tailscale', _('Tailscale Configuration'),
			_('Configure Tailscale VPN settings. Changes take effect after Save & Apply.'));

		s = m.section(form.NamedSection, 'settings', 'tailscale', _('General Settings'));
		s.anonymous = false;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Enable'),
			_('Enable or disable the Tailscale service.'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'port', _('Port'),
			_('UDP port for WireGuard traffic.'));
		o.datatype = 'port';
		o.default = '41641';
		o.rmempty = false;

		o = s.option(form.ListValue, 'tun_mode', _('TUN Mode'),
			_('Network mode for Tailscale.'));
		o.value('auto', _('Auto (prefer kernel, fallback to userspace)'));
		o.value('kernel', _('Kernel'));
		o.value('userspace', _('Userspace'));
		o.default = 'auto';

		o = s.option(form.ListValue, 'proxy_listen', _('Proxy Listen'),
			_('Proxy listen scope for SOCKS5/HTTP proxy in userspace mode.'));
		o.value('localhost', _('Localhost only'));
		o.value('lan', _('LAN (0.0.0.0)'));
		o.default = 'localhost';
		o.depends('tun_mode', 'userspace');

		o = s.option(form.ListValue, 'fw_mode', _('Firewall Mode'),
			_('Firewall backend used by tailscaled.'));
		o.value('nftables', _('nftables (fw4)'));
		o.value('iptables', _('iptables (fw3)'));
		o.default = 'nftables';

		o = s.option(form.Flag, 'auto_update', _('Auto Update'),
			_('Automatically check for and install Tailscale updates via cron.'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Flag, 'log_stdout', _('Log stdout'),
			_('Enable stdout logging for tailscaled.'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Flag, 'log_stderr', _('Log stderr'),
			_('Enable stderr logging for tailscaled.'));
		o.default = '1';
		o.rmempty = false;

		s = m.section(form.NamedSection, 'settings', 'tailscale', _('Installation Info'));
		s.anonymous = false;
		s.addremove = false;

		o = s.option(form.DummyValue, 'storage_mode', _('Storage Mode'));
		o.default = _('N/A');

		o = s.option(form.DummyValue, 'download_source', _('Download Source'));
		o.default = _('N/A');

		o = s.option(form.DummyValue, 'bin_dir', _('Binary Directory'));
		o.default = _('N/A');

		return m.render();
	}
});
