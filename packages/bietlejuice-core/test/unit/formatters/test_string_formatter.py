import unittest

from bietlejuice.formatters.string_formatter import StringFormatter


class TestStringFormatterProperNoun(unittest.TestCase):
    """Unit tests for proper-noun phrase normalization."""

    def test_format_proper_noun_brazil_portugal(self):
        self.assertEqual(
            StringFormatter.format_proper_noun("FULANO DA SILVA"),
            "Fulano da Silva",
        )

    def test_format_proper_noun_removes_accents(self):
        self.assertEqual(
            StringFormatter.format_proper_noun("JOSÉ ÂNGELO"),
            "Jose Angelo",
        )

    def test_format_proper_noun_first_word_particle_capitalized(self):
        self.assertEqual(
            StringFormatter.format_proper_noun("da silva neto"),
            "Da Silva Neto",
        )

    def test_format_proper_noun_hyphen_segments(self):
        self.assertEqual(
            StringFormatter.format_proper_noun("JEAN-PIERRE OLIVEIRA"),
            "Jean-Pierre Oliveira",
        )

    def test_format_proper_noun_spanish_particles(self):
        self.assertEqual(
            StringFormatter.format_proper_noun("GARCIA Y LOPEZ DE LA ROSA"),
            "Garcia y Lopez de la Rosa",
        )

    def test_format_proper_noun_dutch_german_particles(self):
        self.assertEqual(
            StringFormatter.format_proper_noun("VAN DER BERG"),
            "Van der Berg",
        )

    def test_format_proper_noun_mc_all_caps(self):
        self.assertEqual(
            StringFormatter.format_proper_noun("MCDONALD"),
            "McDonald",
        )

    def test_format_proper_noun_machado_not_mc_heuristic(self):
        self.assertEqual(
            StringFormatter.format_proper_noun("machado"),
            "Machado",
        )

    def test_format_proper_noun_none_and_blank(self):
        self.assertIsNone(StringFormatter.format_proper_noun(None))
        self.assertIsNone(StringFormatter.format_proper_noun("   "))
