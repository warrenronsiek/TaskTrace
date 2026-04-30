const HtmlWebpackPlugin = require('html-webpack-plugin');
const CopyWebpackPlugin = require('copy-webpack-plugin');
const path = require('path');

const PATHS = {
  dist: path.join(__dirname, 'dist'),
  src: path.join(__dirname, 'src'),
  public: path.join(__dirname, 'public'),
  node_modules: path.join(__dirname, 'node_modules'),
};

/** @type {import('webpack').Configuration} */
module.exports = {
  entry: './src/index.tsx',
  output: {
    filename: '[name].[contenthash].js',
    path: PATHS.dist,
    publicPath: '/',
    clean: true,
  },
  context: __dirname,
  resolve: {
    extensions: ['.tsx', '.ts', '.js'],
  },
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        use: 'ts-loader',
        exclude: PATHS.node_modules,
      },
      {
        test: /\.css$/,
        use: ['style-loader', 'css-loader'],
        include: [PATHS.src, PATHS.node_modules],
      },
      {
        test: /\.(woff|woff2|eot|ttf)$/,
        type: 'asset/resource',
      },
      {
        test: /\.(svg|ico|png|jpg|jpeg|gif)$/,
        type: 'asset/resource',
        include: [PATHS.src, PATHS.public],
      },
    ],
  },
  plugins: [
    new HtmlWebpackPlugin({
      title: 'TaskTrace',
      template: path.join(__dirname, 'public', 'index.html'),
    }),
    new CopyWebpackPlugin({
      patterns: [
        { from: PATHS.public, to: PATHS.dist, globOptions: { ignore: ['**/index.html'] } },
      ],
    }),
  ],
};
