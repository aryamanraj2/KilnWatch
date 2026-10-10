"""Deterministic checks on every model answer before it leaves the Lambda."""
import re

# The only list of banned stems: any word that starts with one is banned (the leading \b spares "paralegal").
# Prompts and messages reference this constant rather than repeating the words.
BANNED_WORDS = ('illegal', 'unlawful', 'violat')
BANNED = re.compile(r'\b(?:' + '|'.join(BANNED_WORDS) + r')\w*', re.IGNORECASE)
# Any KW- token, including shortened or mangled ones ("KW-6b3b…", "kw-00C5"); each must equal a returned ID exactly.
KILN_TOKEN = re.compile(r'\bKW-[0-9A-Za-z]*', re.IGNORECASE)
# Rule IDs have three segments (C-HAB-800, UP-SCH-1K, UP/HR-SCH-1K, C-TECH-10K); kiln IDs have two (KW-<hex|digits>).
RULE_ID = re.compile(r'\b[A-Z]{1,4}(?:/[A-Z]{1,4})?-[A-Z]{2,6}-[0-9]+[KM]?\b')


def citations(answer):
    """Kiln IDs in order of first appearance, de-duplicated."""
    return list(dict.fromkeys(KILN_TOKEN.findall(answer)))


def check(answer, known_ids):
    """Return None when the answer passes, else a reason the model can act on."""
    if not isinstance(answer, str) or not answer.strip():
        return 'Your answer was empty.'
    for token in citations(answer):
        if token not in known_ids:
            return f'Your answer cited {token}, which no tool returned in this request. Cite only full kiln IDs exactly as tools returned them.'
    if RULE_ID.search(answer):
        return 'Your answer cited a rule ID, but no siting rules have been evaluated.'
    if BANNED.search(answer):
        return 'Your answer used a banned word. Say "flagged by satellite, pending inspection" instead.'
    return None
