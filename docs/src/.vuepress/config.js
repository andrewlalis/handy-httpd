const { description } = require('../../package')
const ddoc_link = require('../ddoc-link')

module.exports = {
  /**
   * Ref：https://v1.vuepress.vuejs.org/config/#title
   */
  title: 'Handy-Httpd',
  /**
   * Ref：https://v1.vuepress.vuejs.org/config/#description
   */
  description: 'Documentation for the Handy-Httpd server.',

  base: '/handy-httpd/',

  /**
   * Extra tags to be injected to the page HTML `<head>`
   *
   * ref：https://v1.vuepress.vuejs.org/config/#head
   */
  head: [
    ['meta', { name: 'theme-color', content: '#ff3900' }],
    ['meta', { name: 'apple-mobile-web-app-capable', content: 'yes' }],
    ['meta', { name: 'apple-mobile-web-app-status-bar-style', content: 'black' }]
  ],

  /**
   * Theme configuration, here is the default theme configuration for VuePress.
   *
   * ref：https://v1.vuepress.vuejs.org/theme/default-theme-config.html
   */
  themeConfig: {
    repo: '',
    editLinks: false,
    docsDir: '',
    editLinkText: '',
    lastUpdated: false,
    sidebarDepth: 3,
    displayAllHeaders: false,
    nav: [
      {
        text: 'Guide',
        link: '/guide/',
      },
      {
        text: 'GitHub',
        link: 'https://github.com/andrewlalis/handy-httpd'
      },
      {
        text: 'code.dlang.org',
        link: 'https://code.dlang.org/packages/handy-httpd'
      },
      {
        text: 'ddoc',
        link: '/handy-httpd/ddoc/index.html',
        target: '_blank'
      }
    ],
    sidebar: {
      '/guide/': [
        {
          title: 'Guide',
          collapsable: false,
          children: [
            '',
            'about',
            'handling-requests',
            'logging',
            'configuration',
            'pre-made-handlers'
          ]
        }
      ],
    }
  },

  /**
   * Apply plugins，ref：https://v1.vuepress.vuejs.org/zh/plugin/
   */
  plugins: [
    '@vuepress/plugin-back-to-top',
    '@vuepress/plugin-medium-zoom',
    ['vuepress-plugin-code-copy', {
      backgroundTransition: false,
      staticIcon: false,
      color: '#ff3900',
      successText: 'Copied to clipboard.'
    }],
    [ddoc_link({
      version: '5.0.0',
      moduleName: 'handy-httpd'
    })]
  ]
}
