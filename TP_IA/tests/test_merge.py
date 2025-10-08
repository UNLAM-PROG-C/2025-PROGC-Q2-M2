from src.merge import merge_segments


def test_merge_unifies_segments_across_tiles():
    segments = [
        {"x1": 10.0, "y1": 50.0, "x2": 120.0, "y2": 52.0, "angle": 0.0, "score": 110.0, "detector": "hough", "tile_id": 0},
        {"x1": 118.0, "y1": 51.0, "x2": 240.0, "y2": 50.0, "angle": 1.0, "score": 122.0, "detector": "hough", "tile_id": 1},
    ]
    merged = merge_segments(segments, distance_threshold=10.0, angle_threshold=5.0)
    assert len(merged) == 1
    combined = merged[0]
    assert combined["x1"] <= 10.0
    assert combined["x2"] >= 240.0
    assert set(combined["source_tiles"]) == {0, 1}
