// A10 Mishandling of Exceptional Conditions fixture - empty catch block
// This is a SYNTHETIC example for scanner regression testing only.
// Not production code.

async function transferFunds(fromId, toId, amount) {
  try {
    await db.debit(fromId, amount);
    await db.credit(toId, amount);
  } catch (err) {}
  // VULNERABLE: exception swallowed silently; partial transfer may leave
  // accounts in inconsistent state with no log or rollback
}
