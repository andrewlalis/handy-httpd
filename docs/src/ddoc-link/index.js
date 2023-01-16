const { path } = require('@vuepress/shared-utils');

module.exports = (options, ctx) => {
    return {
        name: 'ddoc-link',
        define: {
            version: options.version,
            moduleName: options.moduleName
        },
        clientRootMixin: path.resolve(__dirname, 'clientRootMixin.js')
    }
};