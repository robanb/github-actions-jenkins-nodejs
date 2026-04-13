const errorHandler = require('../src/middleware/error-handler');

function createMockRes() {
  const res = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res;
}

describe('errorHandler middleware', () => {
  const originalError = console.error;

  beforeEach(() => {
    console.error = jest.fn();
  });

  afterEach(() => {
    console.error = originalError;
  });

  it('uses the error status when provided', () => {
    const req = { method: 'GET', originalUrl: '/boom' };
    const res = createMockRes();
    const err = new Error('nope');
    err.status = 400;

    errorHandler(err, req, res, () => {});

    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith({
      error: { status: 400, message: 'nope' },
    });
    expect(console.error).not.toHaveBeenCalled();
  });

  it('defaults to 500 and logs when no status is supplied', () => {
    const req = { method: 'POST', originalUrl: '/kaboom' };
    const res = createMockRes();
    const err = new Error('exploded');

    errorHandler(err, req, res, () => {});

    expect(res.status).toHaveBeenCalledWith(500);
    expect(res.json).toHaveBeenCalledWith({
      error: { status: 500, message: 'exploded' },
    });
    expect(console.error).toHaveBeenCalledTimes(1);
  });

  it('falls back to a default message when the error has none', () => {
    const req = { method: 'GET', originalUrl: '/empty' };
    const res = createMockRes();
    const err = new Error();
    err.message = '';
    err.status = 500;

    errorHandler(err, req, res, () => {});

    expect(res.json).toHaveBeenCalledWith({
      error: { status: 500, message: 'Internal Server Error' },
    });
  });
});
