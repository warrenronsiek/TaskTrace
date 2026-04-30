const { merge } = require('webpack-merge');
const webpack = require('webpack');
const common = require('./webpack.common.js');

module.exports = merge(common, {
  mode: 'development',
  devtool: 'eval-source-map',
  output: {
    filename: '[name].bundle.js',
  },
  devServer: {
    static: { directory: require('path').join(__dirname, 'dist') },
    historyApiFallback: true,
    host: process.env.HOST || 'localhost',
    port: process.env.PORT || 3000,
    hot: true,
    open: true,
  },
  plugins: [
    new webpack.DefinePlugin({
      'process.env.ENV': JSON.stringify('dev'),
    }),
  ],
});
