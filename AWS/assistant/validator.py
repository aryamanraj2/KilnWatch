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
CLOCK = re.compile(r'\b\d{1,2}:\d{2}\b')
ESTIMATE = re.compile(r'\bestimat', re.IGNORECASE)


def citations(answer):
    """Kiln IDs in order of first appearance, de-duplicated."""
    return list(dict.fromkeys(KILN_TOKEN.findall(answer)))


def check(answer, known_ids, known_rules=(), route_planned=False):
    """Return None when the answer passes, else a reason the model can act on.
    route_planned: plan_route ran in this request, so any clock time in the answer is a route estimate."""
    if not isinstance(answer, str) or not answer.strip():
        return 'Your answer was empty.'
    for token in citations(answer):
        if token not in known_ids:
            return f'Your answer cited {token}, which no tool returned in this request. Cite only full kiln IDs exactly as tools returned them.'
    for rule in RULE_ID.findall(answer):
        if rule not in known_rules:
            return f'Your answer cited rule {rule}, which no tool returned in this request. Cite only rule IDs exactly as tools returned them.'
    if BANNED.search(answer):
        return 'Your answer used a banned word. Say "flagged by satellite, pending inspection" instead.'
    if route_planned and CLOCK.search(answer) and not ESTIMATE.search(answer):
        return "Call the times estimates, for example 'estimated arrival 09:13'."
    return None
