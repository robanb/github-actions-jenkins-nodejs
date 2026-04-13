function errorHandler(err, req, res, _next) {
  const status = err.status || 500;
  const payload = {
    error: {
      status,
      message: err.message || 'Internal Server Error',
    },
  };

  if (status >= 500) {
    console.error(`[error] ${req.method} ${req.originalUrl}:`, err);
  }

  res.status(status).json(payload);
}

module.exports = errorHandler;
