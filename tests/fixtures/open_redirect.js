// A01 Broken Access Control fixture - open redirect
// This is a SYNTHETIC example for scanner regression testing only.
// Not production code.

const express = require('express');
const router = express.Router();

// VULNERABLE: redirect target controlled by user-supplied query param passed directly
router.get('/login/callback', (req, res) => {
  res.redirect(req.query.next);
});

module.exports = router;
