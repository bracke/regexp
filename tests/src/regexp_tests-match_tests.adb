with Regexp;
with Regexp_Tests.Support;

package body Regexp_Tests.Match_Tests is
   use Regexp;
   use Regexp_Tests.Support;

   procedure Test_Core_Matching (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Match ("abc", "xxabcxx", Match_Ok, "literal match", 3, 5);
      Check_Match ("abc", "abx", No_Match, "literal no match");
      Check_Match ("a.c", "xxabc", Match_Ok, "dot match", 3, 5);
      Check_Match ("a.c", "a" & Character'Val (10) & "c", No_Match, "dot no line break");
      Check_Match ("a.c", "a" & Character'Val (13) & "c", No_Match, "dot no carriage return");
      Check_Match ("^abc", "abcdef", Match_Ok, "start anchor", 1, 3);
      Check_Match ("abc$", "xxabc", Match_Ok, "end anchor", 3, 5);
      Check_Match ("abc$", "abc" & Character'Val (10), No_Match, "end anchor not before LF");
      Check_Match ("ab*c", "ac", Match_Ok, "star zero", 1, 2);
      Check_Match ("ab*c", "abbbc", Match_Ok, "star many", 1, 5);
      Check_Match ("ab+c", "ac", No_Match, "plus requires one");
      Check_Match ("ab+c", "abbc", Match_Ok, "plus many", 1, 4);
      Check_Match ("ab?c", "ac", Match_Ok, "question zero", 1, 2);
      Check_Match ("ab?c", "abc", Match_Ok, "question one", 1, 3);
      Check_Match ("a*", "bbb", Match_Ok, "zero length", 1, 0);
      Check_Match ("b*", "aaab", Match_Ok, "zero length before later non-zero match", 1, 0);
      Check_Match ("^$", "", Match_Ok, "empty text anchors", 1, 0);
      Check_Match ("^a*$", "aaa", Match_Ok, "entire anchored star", 1, 3);
      Check_Match ("a*", "", Match_Ok, "empty text zero length", 1, 0);
      Check_Match ("a*", "aaa", Match_Ok, "star longest", 1, 3);
      Check_Match ("a*", "bbb", No_Match, "entire zero length over non-empty", Entire => True);
   end Test_Core_Matching;

   procedure Test_Character_Classes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Match ("[a-c]+", "xxbca", Match_Ok, "class match", 3, 5);
      Check_Match ("[A-C]+", "xxbca", Match_Ok, "case-insensitive class", 3, 5);
      Check_Match ("[A-Z]+", "--abc", Match_Ok, "case-insensitive range", 3, 5);
      Check_Match
        ("[A-C]+",
         "xxbca",
         No_Match,
         "case-sensitive class",
         Options => (Case_Sensitive => True, others => <>));
      Check_Match ("[a-]+", "xxa-a", Match_Ok, "trailing hyphen class match", 3, 5);
      Check_Match ("[-a]+", "xx-a", Match_Ok, "leading hyphen class match", 3, 4);
      Check_Match ("[\-\]]+", "xx-]", Match_Ok, "escaped class literals", 3, 4);
      Check_Match ("[a-cx]+", "yyabcx", Match_Ok, "mixed range and literal", 3, 6);
      Check_Match ("[^a]+", "aaabb", Match_Ok, "negated class", 4, 5);
      Check_Match ("[^A]+", "aaa", No_Match, "case-insensitive negated class");
      Check_Match
        ("[^A]+",
         "bbb",
         Match_Ok,
         "case-insensitive negated class accepts other letters",
         1,
         3);
      Check_Match
        ("[^A]+",
         "aaa",
         Match_Ok,
         "case-sensitive negated class accepts lowercase a",
         1,
         3,
         Options => (Case_Sensitive => True, others => <>));
      Check_Match ("\d+", "ab123", Match_Ok, "digit class", 3, 5);
      Check_Match ("\D+", "123ab", Match_Ok, "non-digit class", 4, 5);
      Check_Match ("[^\d]+", "123ab", Match_Ok, "negated digit class", 4, 5);
      Check_Match ("\w+", "--a_1", Match_Ok, "word class", 3, 5);
      Check_Match ("\W+", "ab--", Match_Ok, "non-word class", 3, 4);
      Check_Match ("\s+", "ab cd", Match_Ok, "space class", 3, 3);
      Check_Match ("\s+", "ab" & Character'Val (9) & "cd", Match_Ok, "tab class", 3, 3);
      Check_Match ("\s+", "ab" & Character'Val (10) & "cd", Match_Ok, "lf class", 3, 3);
      Check_Match ("\s+", "ab" & Character'Val (13) & "cd", Match_Ok, "cr class", 3, 3);
      Check_Match ("\S+", "  ab", Match_Ok, "non-space class", 3, 4);
   end Test_Character_Classes;

   procedure Test_Escaped_Literals (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Match ("\.", "x.", Match_Ok, "escaped dot", 2, 2);
      Check_Match ("\*", "x*", Match_Ok, "escaped star", 2, 2);
      Check_Match ("\+", "x+", Match_Ok, "escaped plus", 2, 2);
      Check_Match ("\?", "x?", Match_Ok, "escaped question", 2, 2);
      Check_Match ("\(", "x(", Match_Ok, "escaped open paren", 2, 2);
      Check_Match ("\)", "x)", Match_Ok, "escaped close paren", 2, 2);
      Check_Match ("\[", "x[", Match_Ok, "escaped open bracket", 2, 2);
      Check_Match ("\]", "x]", Match_Ok, "escaped close bracket", 2, 2);
      Check_Match ("\{", "x{", Match_Ok, "escaped open brace", 2, 2);
      Check_Match ("\}", "x}", Match_Ok, "escaped close brace", 2, 2);
      Check_Match ("\\", "x\", Match_Ok, "escaped backslash", 2, 2);
      Check_Match ("\^", "x^", Match_Ok, "escaped caret", 2, 2);
      Check_Match ("\$", "x$", Match_Ok, "escaped dollar", 2, 2);
   end Test_Escaped_Literals;

   procedure Test_Match_Options (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Match ("abc", "ABC", Match_Ok, "case insensitive default", 1, 3);
      Check_Match
        ("abc",
         "ABC",
         No_Match,
         "case sensitive",
         Options => (Case_Sensitive => True, others => <>));
      Check_Match
        ("cat",
         "a cat b",
         Match_Ok,
         "whole word positive",
         3,
         5,
         Options => (Whole_Word => True, others => <>));
      Check_Match
        ("cat",
         "scatter",
         No_Match,
         "whole word negative",
         Options => (Whole_Word => True, others => <>));
      Check_Match
        ("^",
         "abc",
         No_Match,
         "whole word start anchor before word",
         Options => (Whole_Word => True, others => <>));
      Check_Match
        ("^",
         " abc",
         Match_Ok,
         "whole word start anchor before space",
         1,
         0,
         Options => (Whole_Word => True, others => <>));
      Check_Match
        ("cat",
         "cat_1",
         No_Match,
         "whole word rejects underscore suffix",
         Options => (Whole_Word => True, others => <>));
      Check_Match
        ("cat",
         "cat1",
         No_Match,
         "whole word rejects digit suffix",
         Options => (Whole_Word => True, others => <>));
      Check_Match
        ("cat",
         "cat",
         Match_Ok,
         "whole word entire positive",
         1,
         3,
         Options => (Whole_Word => True, others => <>),
         Entire => True);
      Check_Match
        ("cat",
         "cat1",
         No_Match,
         "whole word entire negative",
         Options => (Whole_Word => True, others => <>),
         Entire => True);
      Check_Match
        ("abc",
         "ABC",
         No_Match,
         "matches entire case sensitive",
         Options => (Case_Sensitive => True, others => <>),
         Entire => True);
   end Test_Match_Options;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Regexp match tests");
   end Name;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Core_Matching'Access), "Core matching");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Character_Classes'Access), "Character classes");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Escaped_Literals'Access), "Escaped literal matching");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Match_Options'Access), "Match options");
   end Register_Tests;
end Regexp_Tests.Match_Tests;
