import resolve from '@rollup/plugin-node-resolve';

export default {
  input: 'src/cannister_frontend/src/App.js',
  output: {
    file: 'bundle.js',
    format: 'es'
  },
  plugins: [
    resolve()
  ]
};
