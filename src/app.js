const express = require('express');

const routes = require('./routes');
const notFoundHandler = require('./middleware/not-found');
const errorHandler = require('./middleware/error-handler');

function createApp() {
  const app = express();

  app.disable('x-powered-by');
  app.use(express.json());

  app.use('/', routes);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}

module.exports = createApp();
module.exports.createApp = createApp;
