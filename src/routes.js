const { Router } = require('express');

const { version } = require('../package.json');

const router = Router();

router.get('/', (req, res) => {
  res.json({
    message: 'Hello, CI/CD! Running on self-hosted runner.',
    service: 'nodejs-ci-demo',
    version,
  });
});

router.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  });
});

router.get('/sum', (req, res, next) => {
  const a = Number(req.query.a);
  const b = Number(req.query.b);

  if (Number.isNaN(a) || Number.isNaN(b)) {
    const error = new Error('Query parameters "a" and "b" must be valid numbers.');
    error.status = 400;
    return next(error);
  }

  return res.json({ a, b, result: a + b });
});

module.exports = router;
