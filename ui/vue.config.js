const veuiLoaderOptions = require('veui-theme-dls/veui-loader-options');
const path = require('path');

const proxyTarget = process.env.PROXY_TARGET;

async function before(app, server, compiler) {
    app.get('/cgi-bin/videolist.sh', function(req, res) {
        res.setHeader('Content-Type', 'text/plain');
        res.sendFile(path.resolve(__dirname, 'mock/videolist.txt'));
    });
    app.get('/TeslaCam/a/b/:file', function (req, res) {
        console.log(req.params.file);
        res.setHeader('Content-Type', 'video/mp4');
        res.sendFile(path.resolve(__dirname, 'mock/videos', req.params.file));
    });
}

module.exports = {
    publicPath: '',
    devServer: {
        // https://v4.webpack.js.org/configuration/dev-server/#devserverbefore
        // before,

        proxy: {
            '/*.txt': { target: proxyTarget },
            '/*.log': { target: proxyTarget },
            '/cgi-bin/': { target: proxyTarget },
            '/TeslaCam/': { target: proxyTarget }
        },
        // disableHostCheck: true,
        // host: '0.0.0.0',
        // port: '8001',
        // https: false,
        // public: '192.168.2.100:8001'
    },
    css: {
        loaderOptions: {
            less: {
                javascriptEnabled: true
            },
        },
    },
    transpileDependencies: ['veui'],
    configureWebpack: {
        plugins: [
            require('unplugin-vue-components/webpack')({
                resolvers: [require('unplugin-vue-components/resolvers').VeuiResolver({})]
            }),
        ],
    },
    chainWebpack
};

function chainWebpack(config) {
    config.module
        .rule('veui')
        .test(/\.vue$/)
        .pre()
        .use('veui-loader')
        .loader('veui-loader')
        .tap(() => veuiLoaderOptions);
}
