const request = require('supertest');

const app = require('../src/app');
const { version } = require('../package.json');

describe('GET /', () => {
  it('returns a welcome payload including the service version', async () => {
    const res = await request(app).get('/');

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      message: 'Hello, CI/CD!',
      service: 'nodejs-ci-demo',
      version,
    });
  });
});

describe('GET /health', () => {
  it('returns status ok with uptime and timestamp', async () => {
    const res = await request(app).get('/health');

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(typeof res.body.uptime).toBe('number');
    expect(() => new Date(res.body.timestamp)).not.toThrow();
  });
});

describe('GET /sum', () => {
  it('adds two positive numbers', async () => {
    const res = await request(app).get('/sum').query({ a: 2, b: 3 });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ a: 2, b: 3, result: 5 });
  });

  it('handles negative numbers correctly', async () => {
    const res = await request(app).get('/sum').query({ a: -4, b: 10 });

    expect(res.status).toBe(200);
    expect(res.body.result).toBe(6);
  });

  it('returns 400 when query parameters are not numeric', async () => {
    const res = await request(app).get('/sum').query({ a: 'foo', b: 3 });

    expect(res.status).toBe(400);
    expect(res.body.error).toMatchObject({
      status: 400,
      message: expect.stringContaining('must be valid numbers'),
    });
  });

  it('returns 400 when query parameters are missing', async () => {
    const res = await request(app).get('/sum');

    expect(res.status).toBe(400);
    expect(res.body.error.status).toBe(400);
  });
});

describe('unknown routes', () => {
  it('returns a 404 JSON payload for missing routes', async () => {
    const res = await request(app).get('/does-not-exist');

    expect(res.status).toBe(404);
    expect(res.body.error).toMatchObject({
      status: 404,
      message: expect.stringContaining('Route not found'),
    });
  });
});
