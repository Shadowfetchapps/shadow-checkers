# Shadow — the draughts engine

Shadow searches complete turns (a whole multi-jump is one move) in all three rule sets and runs on worker threads, so the board stays responsive.

## Search

- Iterative deepening with a wall-clock budget, negamax alpha-beta with principal-variation search and light late-move reductions.
- A Zobrist transposition table in fixed-size packed arrays.
- Move ordering: transposition-table move, captures by number of pieces taken, crownings, two killers per ply, and the history heuristic.
- A forced-move extension, and a quiescence phase that keeps searching while the side to move must capture — so Shadow never stops calculating in the middle of an exchange.
- Draw awareness from the real game history: repetition since the last irreversible move, and each variant's move-rule counter.
- All work happens on a private `CheckersEngine` through its compact search interface (`generate_keys`, `make_key`, `unmake_key`); nothing touches the scene tree.

## Evaluation

Material with variant-tuned king values (a short king is worth about one and a half men in English draughts; a flying king about three in Russian and Brazilian), advancement, back-rank guard (the English "bridge"), centre control, mobility, runaway men that can't be stopped from crowning, king centralisation, tempo in endgames, and a preference for trading down when ahead.

## Openings

English games draw on a book of 59 sound openings and three-move-ballot starts written in PDN (`data/opening_book_english.txt`, also embedded in `checkers_book.gd` so exports never miss it). Every line is replayed for legality by the tests. Lower levels add variety with seeded randomness among near-best moves.

## Levels

| Level | Typical depth (English) | Time | Character |
|---|---|---|---|
| Beginner | 2 | ~10 ms | Looks one or two moves ahead and often plays loosely |
| Casual | 4 | ~50 ms | Sees simple shots but not deep ones |
| Club | 6 | ~0.25 s | Punishes loose pieces, plays sensible openings |
| Advanced | 8 | ~1.1 s | Calculates tactics deeply, understands the endgame |
| Expert | 9–10 | ~1.8 s | Deterministic apart from the book |
| Master | 10 | ~2.5 s | Full strength |

Russian and Brazilian games search about one ply shallower because flying kings have far more moves. In test matches the new Master, limited to 0.8 s a move, scored 8.5/9 against the 1.x Master in English draughts.

## Using it

```gdscript
CheckersAI.warmup()
var job := CheckersAI.SearchJob.new()
job.variant = engine.variant
job.start_fen = engine.start_fen
job.moves_uci = moves          # full turns so far
job.level = "club"             # or "analysis" with job.time_ms
var task := WorkerThreadPool.add_task(job.run, true)
# … then engine.find_uci(job.best_uci); job.score_white is in centi-men
```

The same job powers Shadow's moves, the evaluation bar and principal variation, and hints. Setting `job.cancelled` stops a search within milliseconds.
