# A04 Cryptographic Failures fixture - hardcoded secret
# This is a SYNTHETIC example for scanner regression testing only.
# Not production code. The key below is fake and rejected by all real services.

import hashlib

# VULNERABLE: hardcoded API key (fake value for testing only)
api_key = "FAKE_KEY_FOR_TESTING_ONLY_aaabbbccc"

# VULNERABLE: MD5 used for password hashing
def hash_password(password):
    return hashlib.md5(password.encode()).hexdigest()

# VULNERABLE: non-crypto randomness for token generation
import random
def generate_token():
    return str(random.randint(100000, 999999))
