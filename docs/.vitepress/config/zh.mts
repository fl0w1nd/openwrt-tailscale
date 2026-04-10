import type { DefaultTheme, LocaleSpecificConfig } from 'vitepress'

export const zh: LocaleSpecificConfig<DefaultTheme.Config> = {
  lang: 'zh-CN',
  description: '面向 OpenWrt 路由器的 Tailscale 自动更新安装管理器',

  themeConfig: {
    nav: [
      { text: '指南', link: '/zh/guide/installation' },
      { text: '更新日志', link: '/zh/changelog' },
      { text: '路线图', link: '/zh/roadmap' },
    ],

    sidebar: {
      '/zh/guide/': [
        {
          text: '快速开始',
          items: [
            { text: '安装指南', link: '/zh/guide/installation' },
            { text: '下载源说明', link: '/zh/guide/download-sources' },
            { text: '存储模式', link: '/zh/guide/storage-modes' },
          ],
        },
        {
          text: '网络配置',
          items: [
            { text: '网络模式', link: '/zh/guide/net-mode' },
            { text: '子网路由', link: '/zh/guide/subnet-routing' },
            { text: '用户空间模式', link: '/zh/guide/userspace-mode' },
          ],
        },
        {
          text: '管理',
          items: [
            { text: 'CLI 命令参考', link: '/zh/guide/commands' },
            { text: 'UCI 配置', link: '/zh/guide/configuration' },
            { text: '自动更新', link: '/zh/guide/auto-update' },
            { text: 'LuCI 界面', link: '/zh/guide/luci' },
          ],
        },
        {
          text: '其他',
          items: [
            { text: '故障排查', link: '/zh/guide/troubleshooting' },
            { text: '卸载说明', link: '/zh/guide/uninstall' },
          ],
        },
      ],
      '/zh/changelog': [
        { text: '更新日志', link: '/zh/changelog' },
      ],
      '/zh/roadmap': [
        { text: '路线图', link: '/zh/roadmap' },
      ],
    },

    editLink: {
      pattern: 'https://github.com/fl0w1nd/openwrt-tailscale/edit/main/docs/:path',
      text: '在 GitHub 上编辑此页',
    },

    outline: { label: '本页目录' },
    lastUpdated: { text: '最后更新' },
    docFooter: { prev: '上一篇', next: '下一篇' },
    darkModeSwitchLabel: '主题',
    sidebarMenuLabel: '菜单',
    returnToTopLabel: '返回顶部',
  },
}
