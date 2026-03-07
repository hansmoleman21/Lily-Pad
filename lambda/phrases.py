"""
Lily Pad — phrase configuration.

Edit this file to add voice-to-text aliases or new trigger phrases.
All phrases are matched case-insensitively as substrings of the incoming SMS body.

RECORD structure
----------------
- Simple event types (pee, ate_ground): list of trigger phrases
- Events with attributes (poop, vomit):
    "attributes": dict of { attribute_name: [phrases that imply that attribute] }
    "base":       phrases that match the event but don't imply any specific attribute
    "default_attribute": (optional) attribute to use when only a base phrase matched

Phrases are checked most-specific first: attribute phrases before base phrases.
Within attributes, the order here determines priority if two attributes' phrases
both appear in the same message (first match wins).
"""

# ── Recording ─────────────────────────────────────────────────────────────────

RECORD = {

    "pee": [
        "peed", "pee", "peeing", "urinate", "urinated",
        # Voice-to-text mishears / shortcuts
        "lili pad",   # mishear of "lily peed"
        "lily pad",   # same
    ],

    "poop": {
        "default_attribute": "normal",
        "attributes": {
            # More severe conditions listed first
            "diarrhea": [
                "diarrhea",
                "runny poop", "runny stool",
                "liquid poop", "liquid stool",
                "loose poop", "loose stool",
            ],
            "soft": [
                "soft poop", "soft stool",
                "mushy poop", "mushy stool",
                "soft poo",
            ],
            "normal": [
                "normal poop", "normal stool",
                "regular poop", "regular stool",
                "firm poop", "firm stool",
            ],
        },
        # Matched when no attribute phrase is found; uses default_attribute above
        "base": [
            "pooped", "poop", "pooping", "poo",
        ],
    },

    "vomit": {
        "attributes": {
            "bile": [
                "bile",
                "yellow vomit", "yellow puke",
                "vomited bile", "puked bile",
            ],
            "food": [
                "food vomit", "food puke",
                "vomited food", "puked food",
                "threw up food", "threw up her food", "threw up his food",
            ],
        },
        # No default_attribute — if no qualifier given, attribute is omitted
        "base": [
            "vomited", "vomit", "vomiting",
            "threw up", "throw up",
            "puked", "puke",
            "sick",
        ],
    },

    "ate_ground": [
        "ate off the ground", "ate something off the ground",
        "eating off the ground", "ate from the ground",
        "ate grass", "eating grass",
        "ate dirt", "eating dirt",
        "ate outside", "eating outside",
        "ate something", "ate something bad",
    ],

}

# ── Summary ───────────────────────────────────────────────────────────────────

SUMMARY = [
    "summary today",
    "today's summary",
    "today summary",
    "daily summary",
    "how's lily today",
    "how is lily today",
    "summary",
]

# ── Delete ────────────────────────────────────────────────────────────────────

DELETE = [
    "remove last",
    "delete last",
    "undo last",
    "undo",
    "remove last record",
    "delete last record",
    "remove last entry",
    "delete last entry",
]

# ── Notes ─────────────────────────────────────────────────────────────────────

NOTE_PREFIX = ["note,"]

# ── Queries ───────────────────────────────────────────────────────────────────
# Structure: { query_kind: { event_type: [phrases] } }

QUERY = {

    "last": {
        "poop":      ["last poop", "when poop", "when did lily poop", "when did she poop", "poop?"],
        "pee":       ["last pee", "when pee", "when did lily pee", "when did she pee", "pee?"],
        "vomit":     ["last vomit", "last sick", "when vomit", "when did lily vomit",
                      "when did she throw up", "last threw up"],
        "ate_ground": ["last ate", "when ate", "when did lily eat off", "when did she eat off"],
    },

    "count": {
        "poop":  ["how many poops", "poops today", "poop count", "number of poops"],
        "pee":   ["how many pees", "pees today", "pee count", "number of pees"],
        "vomit": ["how many vomits", "vomits today", "vomit count",
                  "times vomited", "times sick", "times she vomited"],
    },

}
