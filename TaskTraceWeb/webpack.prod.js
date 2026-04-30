const { merge } = require('webpack-merge');
const webpack = require('webpack');
const TerserPlugin = require('terser-webpack-plugin');
const common = require('./webpack.common.js');

module.exports = merge(common, {
  mode: 'production',
  output: {
    chunkFilename: '[name].[contenthash].chunk.js',
  },
  optimization: {
    minimize: true,
    minimizer: [new TerserPlugin({ parallel: true })],
    runtimeChunk: 'single',
    splitChunks: {
      chunks: 'all',
      cacheGroups: {
        react: {
          test: /[\\/]node_modules[\\/](react|react-dom|react-router-dom)[\\/]/,
          name: 'vendor-react',
          chunks: 'all',
          priority: 30,
          enforce: true,
        },
      },
    },
  },
  plugins: [
    new webpack.DefinePlugin({
      'process.env.ENV': JSON.stringify('prod'),
    }),
  ],
});
