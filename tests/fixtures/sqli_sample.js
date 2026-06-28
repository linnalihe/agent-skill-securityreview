// A05 Injection fixture - SQL injection via string concatenation
// This is a SYNTHETIC example for scanner regression testing only.
// Not production code.

const express = require('express');
const db = require('./db');
const router = express.Router();

// VULNERABLE: user input concatenated directly into SQL string
router.get('/user', async (req, res) => {
  const userId = req.query.id;
  const result = await db.query("SELECT * FROM users WHERE id = " + userId);
  res.json(result.rows[0]);
});

module.exports = router;
