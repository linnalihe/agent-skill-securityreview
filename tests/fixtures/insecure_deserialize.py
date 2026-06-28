# A08 Software/Data Integrity Failures fixture - unsafe deserialization
# This is a SYNTHETIC example for scanner regression testing only.
# Not production code.

import pickle
import yaml

# VULNERABLE: pickle.loads on untrusted input
def load_session(data):
    return pickle.loads(data)

# VULNERABLE: yaml.load without Loader (unsafe)
def parse_config(text):
    return yaml.load(text)
