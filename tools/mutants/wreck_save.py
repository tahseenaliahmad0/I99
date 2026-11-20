"""Mutants of what a Wreck does to the save (GDD 11.4, 13.7) for T-RUN-02. All 4 are killed.
    python3 tools/mutants.py T-RUN-02 tools/mutants/wreck_save.py
"""
D = 'src/core/drive_sim.gd'
C = 'src/game/drive_controller.gd'
MUTANTS = [
 (D, '\tcheckpoint = {}\n\trun.table = table', '\trun.table = table', 'the simulation keeps the wrecked night\'s save'),
 (C, 'elif type == "wreck" and sim.run.active:', 'elif type == "wreck" and false:', 'a Wreck leaves the Telling in the file'),
 (C, '\t\t\t# nothing that the file holds.)\n\t\t\tGame.write_save({})', '\t\t\t# nothing that the file holds.)\n\t\t\tGame.write_save(sim.checkpoint)', 'a Wreck writes the last stop again'),
 (C, 'elif type == "wreck" and sim.run.active:', 'elif type == "wreck":', 'a Wreck on a road of no Telling clears the file'),
]
