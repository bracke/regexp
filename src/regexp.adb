package body Regexp is
   pragma SPARK_Mode (On);

   Max_Patches : constant Positive := Default_Max_States * 2;

   type Patch_Field is (Patch_Out_1, Patch_Out_2);

   type Patch is record
      State : State_Index := No_State;
      Field : Patch_Field := Patch_Out_1;
   end record;

   subtype Patch_Count is Natural range 0 .. Max_Patches;
   type Patch_List is array (Positive range <>) of Patch;

   type Fragment is record
      Start     : State_Index := No_State;
      Outs      : Patch_List (1 .. Max_Patches);
      Out_Count : Patch_Count := 0;
   end record;

   type Active_Set is array (Positive range 1 .. Default_Max_States) of Boolean;

   function Nat (Value : Integer) return Natural is
     (if Value < 0 then 0 else Natural (Value));

   function Pos_Or_First (Value : Integer) return Positive is
     (if Value < Positive'First then Positive'First else Positive (Value));

   procedure Advance (Pos : in out Natural)
     with Pre  => Pos < Positive'Last,
          Post => Pos = Pos'Old + 1
   is
   begin
      Pos := Pos + 1;
   end Advance;

   --  Decode the UTF-8 code point beginning at Text (Pos). Length is its byte
   --  length, clamped so Pos + Length stays within Text; a stray, invalid, or
   --  truncated sequence decodes as its single lead byte (lenient -- the awk
   --  layer must tolerate arbitrary bytes rather than fail). Point is the code
   --  point (its lead byte for the one-byte fallbacks).
   procedure Decode_Utf8
     (Text   : String;
      Pos    : Positive;
      Point  : out Code_Point;
      Length : out Positive)
     with Pre  => Pos in Text'Range,
          Post => Length in 1 .. 4 and then Length - 1 <= Text'Last - Pos
   is
      Lead : constant Natural := Character'Pos (Text (Pos));
      Need : Natural;
      CP   : Natural;
   begin
      if Lead < 16#C0# then                       --  ASCII or a stray continuation
         Point := Code_Point (Lead);
         Length := 1;
         return;
      elsif Lead < 16#E0# then
         Need := 2;
         CP := Lead mod 16#20#;
      elsif Lead < 16#F0# then
         Need := 3;
         CP := Lead mod 16#10#;
      elsif Lead < 16#F8# then
         Need := 4;
         CP := Lead mod 16#08#;
      else
         Point := Code_Point (Lead);
         Length := 1;
         return;
      end if;

      if Text'Last - Pos < Need - 1 then           --  truncated at end of text
         Point := Code_Point (Lead);
         Length := 1;
         return;
      end if;
      for K in 1 .. Need - 1 loop
         declare
            B : constant Natural := Character'Pos (Text (Pos + K));
         begin
            if B < 16#80# or else B >= 16#C0# then  --  not a continuation byte
               Point := Code_Point (Lead);
               Length := 1;
               return;
            end if;
            CP := CP * 16#40# + (B mod 16#40#);
         end;
      end loop;

      if CP > Max_Code_Point then                  --  overlong / out of range
         Point := Code_Point (Lead);
         Length := 1;
      else
         Point := Code_Point (CP);
         Length := Need;
      end if;
   end Decode_Utf8;

   function Relative_Offset (First : Integer; Position : Natural) return Natural is
      Base : constant Natural := Nat (First);
   begin
      if Position < Base then
         return 0;
      elsif Position - Base = Natural'Last then
         return Natural'Last;
      else
         return Position - Base + 1;
      end if;
   end Relative_Offset;

   function Is_Digit (Ch : Character) return Boolean is
     (Ch in '0' .. '9');

   function Is_Word (Ch : Character) return Boolean is
     (Ch in 'A' .. 'Z' or else Ch in 'a' .. 'z' or else Ch in '0' .. '9' or else Ch = '_');

   function Is_Word (Ch : Character; Mode : Character_Mode_Type) return Boolean is
   begin
      if Is_Word (Ch) then
         return True;
      end if;

      return Mode = UTF_8_Mode and then Character'Pos (Ch) >= 16#80#;
   end Is_Word;

   function Is_Capture_Name_Start (Ch : Character) return Boolean is
     (Ch in 'A' .. 'Z' or else Ch in 'a' .. 'z' or else Ch = '_');

   function Is_Capture_Name_Char (Ch : Character) return Boolean is
     (Is_Capture_Name_Start (Ch) or else Ch in '0' .. '9');

   function Word_Boundary_Passes
     (Text     : String;
      Position : Natural;
      Options  : Match_Options)
      return Boolean
   is
      Left_Word  : Boolean := False;
      Right_Word : Boolean := False;
   begin
      if Position > Nat (Text'First)
        and then Position - 1 <= Nat (Text'Last)
      then
         Left_Word := Is_Word (Text (Positive (Position - 1)), Options.Character_Mode);
      end if;

      if Position >= Nat (Text'First)
        and then Position <= Nat (Text'Last)
      then
         Right_Word := Is_Word (Text (Positive (Position)), Options.Character_Mode);
      end if;

      return Left_Word /= Right_Word;
   end Word_Boundary_Passes;

   function Fold (Ch : Character) return Character is
   begin
      if Ch in 'A' .. 'Z' then
         return Character'Val (Character'Pos (Ch) - Character'Pos ('A') + Character'Pos ('a'));
      end if;

      return Ch;
   end Fold;

   function Upper (Ch : Character) return Character is
   begin
      if Ch in 'a' .. 'z' then
         return Character'Val (Character'Pos (Ch) - Character'Pos ('a') + Character'Pos ('A'));
      end if;

      return Ch;
   end Upper;

   function Is_Lower (Ch : Character) return Boolean is
     (Ch in 'a' .. 'z');

   function Is_Upper (Ch : Character) return Boolean is
     (Ch in 'A' .. 'Z');

   function Equal_Chars (Left, Right : Character; Case_Sensitive : Boolean) return Boolean is
   begin
      if Case_Sensitive then
         return Left = Right;
      end if;

      return Fold (Left) = Fold (Right);
   end Equal_Chars;

   function Option_Value (Mode : Option_Mode; Default : Boolean) return Boolean is
   begin
      case Mode is
         when Option_Inherit =>
            return Default;
         when Option_Off =>
            return False;
         when Option_On =>
            return True;
      end case;
   end Option_Value;

   function Effective_Case_Sensitive (Node : State; Options : Match_Options) return Boolean is
     (Option_Value (Node.Modes.Case_Sensitive, Options.Case_Sensitive));

   function Effective_Dot_Matches_Newline (Node : State; Options : Match_Options) return Boolean is
     (Option_Value (Node.Modes.Dot_Matches_Newline, Options.Dot_Matches_Newline));

   function Effective_Multiline_Anchors (Node : State; Options : Match_Options) return Boolean is
     (Option_Value (Node.Modes.Multiline_Anchors, Options.Multiline_Anchors));

   procedure Add_Digit (Class : in out Character_Class; Value : Boolean := True) is
   begin
      for Pos in Character'Pos ('0') .. Character'Pos ('9') loop
         Class.Members (Character'Val (Pos)) := Value;
      end loop;
   end Add_Digit;

   procedure Add_Word (Class : in out Character_Class; Value : Boolean := True) is
   begin
      for Pos in Character'Pos ('A') .. Character'Pos ('Z') loop
         Class.Members (Character'Val (Pos)) := Value;
      end loop;
      for Pos in Character'Pos ('a') .. Character'Pos ('z') loop
         Class.Members (Character'Val (Pos)) := Value;
      end loop;
      for Pos in Character'Pos ('0') .. Character'Pos ('9') loop
         Class.Members (Character'Val (Pos)) := Value;
      end loop;
      Class.Members ('_') := Value;
   end Add_Word;

   procedure Add_Whitespace (Class : in out Character_Class; Value : Boolean := True) is
   begin
      Class.Members (' ') := Value;
      Class.Members (Character'Val (9)) := Value;
      Class.Members (Character'Val (10)) := Value;
      Class.Members (Character'Val (11)) := Value;
      Class.Members (Character'Val (12)) := Value;
      Class.Members (Character'Val (13)) := Value;
   end Add_Whitespace;

   procedure Add_Horizontal_Whitespace (Class : in out Character_Class; Value : Boolean := True) is
   begin
      Class.Members (' ') := Value;
      Class.Members (Character'Val (9)) := Value;
   end Add_Horizontal_Whitespace;

   procedure Add_Vertical_Whitespace (Class : in out Character_Class; Value : Boolean := True) is
   begin
      Class.Members (Character'Val (10)) := Value;
      Class.Members (Character'Val (11)) := Value;
      Class.Members (Character'Val (12)) := Value;
      Class.Members (Character'Val (13)) := Value;
   end Add_Vertical_Whitespace;

   procedure Add_Lower (Class : in out Character_Class; Value : Boolean := True) is
   begin
      for Pos in Character'Pos ('a') .. Character'Pos ('z') loop
         Class.Members (Character'Val (Pos)) := Value;
      end loop;
   end Add_Lower;

   procedure Add_Upper (Class : in out Character_Class; Value : Boolean := True) is
   begin
      for Pos in Character'Pos ('A') .. Character'Pos ('Z') loop
         Class.Members (Character'Val (Pos)) := Value;
      end loop;
   end Add_Upper;

   procedure Add_Alpha (Class : in out Character_Class; Value : Boolean := True) is
   begin
      Add_Lower (Class, Value);
      Add_Upper (Class, Value);
   end Add_Alpha;

   procedure Add_Xdigit (Class : in out Character_Class; Value : Boolean := True) is
   begin
      Add_Digit (Class, Value);
      for Pos in Character'Pos ('A') .. Character'Pos ('F') loop
         Class.Members (Character'Val (Pos)) := Value;
      end loop;
      for Pos in Character'Pos ('a') .. Character'Pos ('f') loop
         Class.Members (Character'Val (Pos)) := Value;
      end loop;
   end Add_Xdigit;

   procedure Add_Blank (Class : in out Character_Class; Value : Boolean := True) is
   begin
      Class.Members (' ') := Value;
      Class.Members (Character'Val (9)) := Value;
   end Add_Blank;

   procedure Add_Cntrl (Class : in out Character_Class; Value : Boolean := True) is
   begin
      for Pos in 0 .. 31 loop
         Class.Members (Character'Val (Pos)) := Value;
      end loop;
      Class.Members (Character'Val (127)) := Value;
   end Add_Cntrl;

   procedure Add_Graph (Class : in out Character_Class; Value : Boolean := True) is
   begin
      for Pos in 33 .. 126 loop
         Class.Members (Character'Val (Pos)) := Value;
      end loop;
   end Add_Graph;

   procedure Add_Print (Class : in out Character_Class; Value : Boolean := True) is
   begin
      for Pos in 32 .. 126 loop
         Class.Members (Character'Val (Pos)) := Value;
      end loop;
   end Add_Print;

   procedure Add_Punct (Class : in out Character_Class; Value : Boolean := True) is
   begin
      Add_Graph (Class, Value);
      for Pos in Character'Pos ('A') .. Character'Pos ('Z') loop
         Class.Members (Character'Val (Pos)) := not Value;
      end loop;
      for Pos in Character'Pos ('a') .. Character'Pos ('z') loop
         Class.Members (Character'Val (Pos)) := not Value;
      end loop;
      for Pos in Character'Pos ('0') .. Character'Pos ('9') loop
         Class.Members (Character'Val (Pos)) := not Value;
      end loop;
   end Add_Punct;

   function Equals_No_Case (Left : Character; Right : Character) return Boolean is
   begin
      if Left = Right then
         return True;
      end if;

      return Fold (Left) = Fold (Right);
   end Equals_No_Case;

   function Equals_No_Case (Left : String; Right : String) return Boolean is
   begin
      if Left'Length /= Right'Length then
         return False;
      end if;

      for I in 1 .. Left'Length loop
         if not Equals_No_Case (Left (Left'First + I - 1), Right (Right'First + I - 1)) then
            return False;
         end if;
      end loop;

      return True;
   end Equals_No_Case;

   procedure Apply_Unicode_Property
     (Name  : String;
      Class : out Character_Class;
      Good  : out Boolean)
   is
      Normalized : String := Name;
   begin
      Class := (others => <>);

      if Name'Length = 0 then
         Good := False;
         return;
      end if;

      if Name'Length >= 2
        and then Equals_No_Case (Name (Name'First), 'I')
        and then Equals_No_Case (Name (Name'First + 1), 'S')
      then
         Normalized := Name (Name'First + 2 .. Name'Last);
      else
         Normalized := Name;
      end if;

      for I in Normalized'Range loop
         Normalized (I) := Fold (Normalized (I));
      end loop;

      Class := (others => <>);

      if Equals_No_Case (Normalized, "any") then
         for Ch in Character loop
            Class.Members (Ch) := True;
         end loop;

      elsif Equals_No_Case (Normalized, "ascii") then
         for Ch in Character loop
            if Character'Pos (Ch) <= 16#7F# then
               Class.Members (Ch) := True;
            end if;
         end loop;

      elsif Equals_No_Case (Normalized, "l")
        or else Equals_No_Case (Normalized, "lu")
        or else Equals_No_Case (Normalized, "ll")
        or else Equals_No_Case (Normalized, "lt")
        or else Equals_No_Case (Normalized, "lm")
        or else Equals_No_Case (Normalized, "lo")
        or else Equals_No_Case (Normalized, "alpha")
        or else Equals_No_Case (Normalized, "alphabetic")
      then
         Add_Alpha (Class);

      elsif Equals_No_Case (Normalized, "u")
        or else Equals_No_Case (Normalized, "upper")
        or else Equals_No_Case (Normalized, "uppercase")
      then
         Add_Upper (Class);

      elsif Equals_No_Case (Normalized, "l")
        or else Equals_No_Case (Normalized, "lower")
        or else Equals_No_Case (Normalized, "lowercase")
      then
         Add_Lower (Class);

      elsif Equals_No_Case (Normalized, "n")
        or else Equals_No_Case (Normalized, "nd")
        or else Equals_No_Case (Normalized, "digit")
        or else Equals_No_Case (Normalized, "decimal")
        or else Equals_No_Case (Normalized, "number")
      then
         Add_Digit (Class);

      elsif Equals_No_Case (Normalized, "xdigit")
        or else Equals_No_Case (Normalized, "hex")
        or else Equals_No_Case (Normalized, "hexidigit")
      then
         Add_Xdigit (Class);

      elsif Equals_No_Case (Normalized, "space")
        or else Equals_No_Case (Normalized, "whitespace")
      then
         Add_Whitespace (Class);

      elsif Equals_No_Case (Normalized, "word") then
         Add_Word (Class);

      elsif Equals_No_Case (Normalized, "punct")
        or else Equals_No_Case (Normalized, "punctuation")
      then
         Add_Punct (Class);

      elsif Equals_No_Case (Normalized, "graph") then
         Add_Graph (Class);

      elsif Equals_No_Case (Normalized, "print") then
         Add_Print (Class);

      elsif Equals_No_Case (Normalized, "cntrl")
        or else Equals_No_Case (Normalized, "control")
      then
         Add_Cntrl (Class);

      elsif Equals_No_Case (Normalized, "blank") then
         Add_Blank (Class);

      else
         Good := False;
         return;
      end if;

      Good := True;
   end Apply_Unicode_Property;

   procedure Parse_Unicode_Property
     (Pattern : String;
      Pos     : in out Natural;
      Class   : out Character_Class;
      Status  : out Compile_Status;
      Offset  : out Natural;
      Good    : out Boolean)
   is
      Start : Natural;
      Name  : String (1 .. 64);
      Name_Last : Natural;
   begin
      Class := (others => <>);
      Status := Invalid_Escape;
      Offset := (if Pos = 0 then 0 else Pos);
      Good := False;

      if Pos > Nat (Pattern'Last)
        or else Pattern (Positive (Pos)) not in 'p' | 'P'
        or else Pos + 1 > Nat (Pattern'Last)
        or else Pattern (Positive (Pos + 1)) /= '{'
      then
         return;
      end if;

      Start := Pos + 2;
      if Start > Nat (Pattern'Last) then
         Offset := Start;
         return;
      end if;

      Name_Last := Start;
      while Name_Last <= Nat (Pattern'Last) and then Pattern (Positive (Name_Last)) /= '}' loop
         Name_Last := Name_Last + 1;
      end loop;

      if Name_Last > Nat (Pattern'Last) or else Name_Last = Start then
         Offset := Pos + 1;
         return;
      end if;

      if Name_Last - Start > Name'Length then
         Offset := Name_Last;
         return;
      end if;

      for I in 1 .. Name_Last - Start loop
         Name (I) := Pattern (Positive (Start + I - 1));
      end loop;

      Apply_Unicode_Property (Name (1 .. Name_Last - Start), Class, Good);
      if not Good then
         Offset := Pos + 1;
         return;
      end if;

      if Pattern (Positive (Pos)) = 'P' then
         Class.Negated := True;
      end if;

      Pos := Name_Last + 1;
      Status := Compile_Ok;
      Offset := Pos;
      Good := True;
   end Parse_Unicode_Property;

   procedure Add_Range (Class : in out Character_Class; First, Last : Character) is
   begin
      for Pos in Character'Pos (First) .. Character'Pos (Last) loop
         Class.Members (Character'Val (Pos)) := True;
      end loop;
   end Add_Range;

   --  Append one code-point interval (> U+00FF) to a compile-time class; a full
   --  interval table is dropped silently rather than corrupting the class.
   procedure Add_Hi_Interval (Class : in out Character_Class; Lo, Hi : Code_Point) is
   begin
      if Hi >= Lo and then Class.Hi_Count < Max_Class_Intervals then
         Class.Hi_Count := Class.Hi_Count + 1;
         Class.Hi_Ranges (Class.Hi_Count) := (Lo, Hi);
      end if;
   end Add_Hi_Interval;

   --  Add a code-point range: the <= U+00FF part goes in the byte-set Members,
   --  the > U+00FF part becomes an interval.
   procedure Add_Code_Range (Class : in out Character_Class; Lo, Hi : Code_Point) is
   begin
      if Lo <= 16#FF# then
         for P in Natural (Lo) .. Natural (Code_Point'Min (Hi, 16#FF#)) loop
            Class.Members (Character'Val (P)) := True;
         end loop;
      end if;
      if Hi > 16#FF# then
         Add_Hi_Interval (Class, Code_Point'Max (Lo, 16#100#), Hi);
      end if;
   end Add_Code_Range;

   procedure Merge (Target : in out Character_Class; Source : Character_Class) is
   begin
      if Source.Negated then
         for Ch in Character loop
            Target.Members (Ch) := Target.Members (Ch) or else not Source.Members (Ch);
         end loop;
         --  A negated ASCII predefined class (\D, \W, \S) contains every code
         --  point above U+00FF, so contribute that whole range.
         Add_Hi_Interval (Target, 16#100#, Max_Code_Point);
      else
         for Ch in Character loop
            Target.Members (Ch) := Target.Members (Ch) or else Source.Members (Ch);
         end loop;
         for K in 1 .. Source.Hi_Count loop
            Add_Hi_Interval (Target, Source.Hi_Ranges (K).Lo, Source.Hi_Ranges (K).Hi);
         end loop;
      end if;
   end Merge;

   function Contains (Class : Character_Class; Ch : Character) return Boolean is
     (if Class.Negated then not Class.Members (Ch) else Class.Members (Ch));

   procedure Intersect (Target : in out Character_Class; Source : Character_Class) is
   begin
      for Ch in Character loop
         Target.Members (Ch) := Contains (Target, Ch) and then Contains (Source, Ch);
      end loop;
      --  A code point > U+00FF survives only if Source also contains it; a
      --  positive ASCII source contains none, so drop the high intervals, while
      --  a negated ASCII source contains them all, so keep them.
      if not Source.Negated then
         Target.Hi_Count := 0;
      end if;
      Target.Negated := False;
   end Intersect;

   procedure Subtract (Target : in out Character_Class; Source : Character_Class) is
   begin
      for Ch in Character loop
         Target.Members (Ch) := Contains (Target, Ch) and then not Contains (Source, Ch);
      end loop;
      --  A negated ASCII source contains every high code point, so subtracting it
      --  removes them all; a positive ASCII source removes none.
      if Source.Negated then
         Target.Hi_Count := 0;
      end if;
      Target.Negated := False;
   end Subtract;

   --  Copy a compiled class into the shared per-Regexp interval pool, returning
   --  the compact form stored in the Node_Class state. High intervals that would
   --  overflow the pool are dropped rather than corrupting indices.
   procedure Store_Class
     (Expr   : in out Regexp;
      C      : Character_Class;
      Result : out Stored_Class)
   is
      First : Class_Pool_Count := 0;
      Count : Class_Pool_Count := 0;
   begin
      if C.Hi_Count > 0 and then Expr.Class_Pool_Used < Max_Class_Pool then
         First := Expr.Class_Pool_Used + 1;
         for K in 1 .. C.Hi_Count loop
            exit when Expr.Class_Pool_Used = Max_Class_Pool;
            Expr.Class_Pool_Used := Expr.Class_Pool_Used + 1;
            Expr.Class_Pool (Expr.Class_Pool_Used) := C.Hi_Ranges (K);
            Count := Count + 1;
         end loop;
      end if;
      if Count = 0 then
         First := 0;
      end if;
      Result := (Negated  => C.Negated,
                 Members  => C.Members,
                 Hi_First => First,
                 Hi_Count => Count);
   end Store_Class;

   --  Byte membership for a stored class (ASCII_Mode matching).
   function Matches_Stored_Byte
     (Class : Stored_Class; Ch : Character; Case_Sensitive : Boolean) return Boolean
   is
      Hit : Boolean := Class.Members (Ch);
   begin
      if not Case_Sensitive then
         Hit := Hit or else Class.Members (Fold (Ch)) or else Class.Members (Upper (Ch));
      end if;
      return (if Class.Negated then not Hit else Hit);
   end Matches_Stored_Byte;

   --  Code-point membership for a stored class (UTF_8_Mode matching).
   function Matches_Stored_CP
     (Class          : Stored_Class;
      Pool           : Class_Pool_Array;
      CP             : Code_Point;
      Case_Sensitive : Boolean)
      return Boolean
   is
      Hit : Boolean := False;
   begin
      if CP <= 16#FF# then
         declare
            Ch : constant Character := Character'Val (Natural (CP));
         begin
            Hit := Class.Members (Ch);
            if not Case_Sensitive then
               Hit := Hit or else Class.Members (Fold (Ch)) or else Class.Members (Upper (Ch));
            end if;
         end;
      elsif Class.Hi_Count > 0
        and then Class.Hi_First >= 1
        and then Class.Hi_First + Class.Hi_Count - 1 <= Max_Class_Pool
      then
         for K in Class.Hi_First .. Class.Hi_First + Class.Hi_Count - 1 loop
            if CP >= Pool (K).Lo and then CP <= Pool (K).Hi then
               Hit := True;
            end if;
         end loop;
      end if;
      return (if Class.Negated then not Hit else Hit);
   end Matches_Stored_CP;

   --  The number of bytes the matcher consumes at Pos: one code point in
   --  UTF_8_Mode, one byte otherwise. Every consuming node and the outer step
   --  use this same width, so the lockstep simulation stays consistent.
   function Step_Width (Expr : Regexp; Text : String; Pos : Positive) return Positive
     with Pre  => Pos in Text'Range,
          Post => Step_Width'Result - 1 <= Text'Last - Pos
   is
      CP : Code_Point;
      L  : Positive;
   begin
      if Expr.Compiled_Mode = UTF_8_Mode then
         Decode_Utf8 (Text, Pos, CP, L);
         return L;
      else
         return 1;
      end if;
   end Step_Width;

   --  Whether a Node_Class state matches the input unit at Pos, honouring the
   --  compiled character mode (code point in UTF_8_Mode, byte otherwise).
   function Class_Matches
     (Expr : Regexp; Node : State; Text : String; Pos : Positive; Case_Sensitive : Boolean)
      return Boolean
     with Pre => Pos in Text'Range
   is
      CP : Code_Point;
      L  : Positive;   --  the code point's width; not needed here beyond decoding
   begin
      if Expr.Compiled_Mode = UTF_8_Mode then
         Decode_Utf8 (Text, Pos, CP, L);
         pragma Assert (L >= 1);   --  consume L (Decode guarantees 1 .. 4)
         return Matches_Stored_CP (Node.Class, Expr.Class_Pool, CP, Case_Sensitive);
      else
         return Matches_Stored_Byte (Node.Class, Text (Pos), Case_Sensitive);
      end if;
   end Class_Matches;

   procedure Append_Out (Frag : in out Fragment; Item : Patch; Ok : out Boolean) is
   begin
      if Frag.Out_Count = Frag.Outs'Length then
         Ok := False;
         return;
      end if;

      Frag.Out_Count := Frag.Out_Count + 1;
      Frag.Outs (Frag.Out_Count) := Item;
      Ok := True;
   end Append_Out;

   procedure Append_Outs (Target : in out Fragment; Source : Fragment; Ok : out Boolean) is
      Added : Boolean;
   begin
      Ok := True;
      for I in 1 .. Source.Out_Count loop
         Append_Out (Target, Source.Outs (I), Added);
         if not Added then
            Ok := False;
            return;
         end if;
      end loop;
   end Append_Outs;

   procedure Patch_To (Expression : in out Regexp; Frag : Fragment; Target : State_Index) is
   begin
      for I in 1 .. Frag.Out_Count loop
         if Frag.Outs (I).State /= No_State then
            case Frag.Outs (I).Field is
               when Patch_Out_1 =>
                  Expression.States (Positive (Frag.Outs (I).State)).Out_1 := Target;
               when Patch_Out_2 =>
                  Expression.States (Positive (Frag.Outs (I).State)).Out_2 := Target;
            end case;
         end if;
      end loop;
   end Patch_To;

   function Capture_Name_Equals
     (Expression : Regexp;
      Index      : Positive;
      Name       : String)
      return Boolean
   is
   begin
      if Index > Max_Captures
        or else Name'Length /= Expression.Capture_Name_Lengths (Index)
      then
         return False;
      end if;

      for I in 1 .. Name'Length loop
         if Expression.Capture_Names (Index) (I) /= Name (Name'First + I - 1) then
            return False;
         end if;
      end loop;

      return True;
   end Capture_Name_Equals;

   function Has_Capture_Name (Expression : Regexp; Name : String) return Boolean is
   begin
      for I in 1 .. Natural'Min (Expression.Capture_Count, Max_Captures) loop
         if Capture_Name_Equals (Expression, I, Name) then
            return True;
         end if;
      end loop;

      return False;
   end Has_Capture_Name;

   function Capture_Name_Index (Expression : Regexp; Name : String) return Natural is
   begin
      for I in 1 .. Natural'Min (Expression.Capture_Count, Max_Captures) loop
         if Capture_Name_Equals (Expression, I, Name) then
            return I;
         end if;
      end loop;

      return 0;
   end Capture_Name_Index;

   procedure Store_Capture_Name
     (Expression : in out Regexp;
      Index      : Positive;
      Name       : String)
   is
   begin
      if Index > Max_Captures then
         return;
      end if;

      Expression.Capture_Name_Lengths (Index) := Name'Length;
      for I in 1 .. Name'Length loop
         Expression.Capture_Names (Index) (I) := Name (Name'First + I - 1);
      end loop;
   end Store_Capture_Name;

   procedure New_State
     (Expression : in out Regexp;
      Kind       : Node_Kind;
      Max_States : Positive;
      Index      : out State_Index)
   is
   begin
      if Expression.State_Count >= Max_States or else Expression.State_Count = Default_Max_States then
         Index := No_State;
         return;
      end if;

      Expression.State_Count := Expression.State_Count + 1;
      Expression.States (Expression.State_Count) := (Kind => Kind, others => <>);
      Index := State_Index (Expression.State_Count);
   end New_State;

   procedure Atom_Fragment
     (Expression : in out Regexp;
      Kind       : Node_Kind;
      Max_States : Positive;
      Frag       : out Fragment;
      Ch         : Character := Character'Val (0);
      Class      : Character_Class := (others => <>);
      Modes      : Scoped_Options := (others => Option_Inherit))
   is
      Index : State_Index;
      Ok    : Boolean;
   begin
      Frag := (others => <>);
      New_State (Expression, Kind, Max_States, Index);
      if Index = No_State then
         return;
      end if;

      Expression.States (Positive (Index)).Ch := Ch;
      declare
         Stored : Stored_Class;
      begin
         Store_Class (Expression, Class, Stored);
         Expression.States (Positive (Index)).Class := Stored;
      end;
      Expression.States (Positive (Index)).Modes := Modes;
      Frag.Start := Index;
      Append_Out (Frag, (State => Index, Field => Patch_Out_1), Ok);
      if not Ok then
         Frag := (others => <>);
      end if;
   end Atom_Fragment;

   procedure Capture_Fragment
     (Expression : in out Regexp;
      Kind       : Node_Kind;
      Capture    : Positive;
      Max_States : Positive;
      Frag       : out Fragment)
   is
      Index : State_Index;
      Ok    : Boolean;
   begin
      Frag := (others => <>);
      New_State (Expression, Kind, Max_States, Index);
      if Index = No_State then
         return;
      end if;

      Expression.States (Positive (Index)).Capture := Capture;
      Frag.Start := Index;
      Append_Out (Frag, (State => Index, Field => Patch_Out_1), Ok);
      if not Ok then
         Frag := (others => <>);
      end if;
   end Capture_Fragment;

   procedure Backreference_Fragment
     (Expression : in out Regexp;
      Capture    : Positive;
      Max_States : Positive;
      Modes      : Scoped_Options;
      Frag       : out Fragment)
   is
      Index : State_Index;
      Ok    : Boolean;
   begin
      Frag := (others => <>);
      New_State (Expression, Node_Backreference, Max_States, Index);
      if Index = No_State then
         return;
      end if;

      Expression.States (Positive (Index)).Capture := Capture;
      Expression.States (Positive (Index)).Modes := Modes;
      Expression.Has_Backreferences := True;
      Frag.Start := Index;
      Append_Out (Frag, (State => Index, Field => Patch_Out_1), Ok);
      if not Ok then
         Frag := (others => <>);
      end if;
   end Backreference_Fragment;

   procedure Lookahead_Fragment
     (Expression : in out Regexp;
      Is_Positive : Boolean;
      Assertion  : Fragment;
      Max_States : Positive;
      Frag       : out Fragment)
   is
      Assert_Match : State_Index;
      Index        : State_Index;
      Ok           : Boolean;
   begin
      Frag := (others => <>);
      New_State (Expression, Node_Lookahead_Match, Max_States, Assert_Match);
      if Assert_Match = No_State then
         return;
      end if;

      Patch_To (Expression, Assertion, Assert_Match);
      New_State
        (Expression,
         (if Is_Positive then Node_Lookahead_Positive else Node_Lookahead_Negative),
         Max_States,
         Index);
      if Index = No_State then
         return;
      end if;

      Expression.States (Positive (Index)).Out_2 := Assertion.Start;
      Frag.Start := Index;
      Append_Out (Frag, (State => Index, Field => Patch_Out_1), Ok);
      if not Ok then
         Frag := (others => <>);
      end if;
   end Lookahead_Fragment;

   function Atomic_Subpattern_Supported
     (Expression  : Regexp;
      First_State : Positive;
      Last_State  : Natural)
      return Boolean
   is
   begin
      if Last_State < First_State then
         return True;
      end if;

      for I in First_State .. Last_State loop
         if Expression.States (I).Kind in Node_Capture_Start | Node_Capture_End | Node_Backreference then
            return False;
         end if;
      end loop;

      return True;
   end Atomic_Subpattern_Supported;

   procedure Atomic_Fragment
     (Expression : in out Regexp;
      Assertion  : Fragment;
      Max_States : Positive;
      Frag       : out Fragment)
   is
      Assert_Match : State_Index;
      Index        : State_Index;
      Ok           : Boolean;
   begin
      Frag := (others => <>);
      New_State (Expression, Node_Lookahead_Match, Max_States, Assert_Match);
      if Assert_Match = No_State then
         return;
      end if;

      Patch_To (Expression, Assertion, Assert_Match);
      New_State (Expression, Node_Atomic, Max_States, Index);
      if Index = No_State then
         return;
      end if;

      Expression.States (Positive (Index)).Out_2 := Assertion.Start;
      Expression.Has_Atomic := True;
      Frag.Start := Index;
      Append_Out (Frag, (State => Index, Field => Patch_Out_1), Ok);
      if not Ok then
         Frag := (others => <>);
      end if;
   end Atomic_Fragment;

   procedure Assertion_Fixed_Width
     (Expression : Regexp;
      Start      : State_Index;
      Match      : State_Index;
      Width      : out Natural;
      Fixed      : out Boolean)
   is
      Visiting : Active_Set := [others => False];

      procedure State_Width
        (Index : State_Index;
         Value : out Natural;
         Good  : out Boolean)
      is
         Left_Good  : Boolean;
         Right_Good : Boolean;
         Left       : Natural;
         Right      : Natural;
      begin
         Value := 0;
         Good := False;

         if Index = No_State then
            return;
         elsif Index = Match then
            Good := True;
            return;
         elsif Visiting (Positive (Index)) then
            return;
         end if;

         Visiting (Positive (Index)) := True;

         declare
            Node : constant State := Expression.States (Positive (Index));
         begin
            case Node.Kind is
               when Node_Char | Node_Any | Node_Class =>
                  State_Width (Node.Out_1, Left, Left_Good);
                  if Left_Good and then Left < Natural'Last then
                     Value := Left + 1;
                     Good := True;
                  end if;

               when Node_Split =>
                  State_Width (Node.Out_1, Left, Left_Good);
                  State_Width (Node.Out_2, Right, Right_Good);
                  if Left_Good and then Right_Good and then Left = Right then
                     Value := Left;
                     Good := True;
                  end if;

               when Node_Start_Line
                  | Node_End_Line
                  | Node_Word_Boundary
                  | Node_Not_Word_Boundary
                  | Node_Lookahead_Positive
                  | Node_Lookahead_Negative
                  | Node_Lookbehind_Positive
                  | Node_Lookbehind_Negative
                  | Node_Capture_Start
                  | Node_Capture_End =>
                  State_Width (Node.Out_1, Value, Good);

               when others =>
                  null;
            end case;
         end;

         Visiting (Positive (Index)) := False;
      end State_Width;
   begin
      State_Width (Start, Width, Fixed);
   end Assertion_Fixed_Width;

   procedure Lookbehind_Fragment
     (Expression  : in out Regexp;
      Is_Positive : Boolean;
      Assertion   : Fragment;
      Max_States  : Positive;
      Frag        : out Fragment;
      Fixed       : out Boolean)
   is
      Assert_Match : State_Index;
      Index        : State_Index;
      Ok           : Boolean;
      Width        : Natural;
   begin
      Frag := (others => <>);
      Fixed := False;
      New_State (Expression, Node_Lookahead_Match, Max_States, Assert_Match);
      if Assert_Match = No_State then
         return;
      end if;

      Patch_To (Expression, Assertion, Assert_Match);
      Assertion_Fixed_Width (Expression, Assertion.Start, Assert_Match, Width, Fixed);
      if not Fixed then
         return;
      end if;

      New_State
        (Expression,
         (if Is_Positive then Node_Lookbehind_Positive else Node_Lookbehind_Negative),
         Max_States,
         Index);
      if Index = No_State then
         return;
      end if;

      Expression.States (Positive (Index)).Out_2 := Assertion.Start;
      Expression.States (Positive (Index)).Capture := Width;
      Frag.Start := Index;
      Append_Out (Frag, (State => Index, Field => Patch_Out_1), Ok);
      if not Ok then
         Frag := (others => <>);
      end if;
   end Lookbehind_Fragment;

   procedure Concat
     (Expression : in out Regexp;
      Left       : in out Fragment;
      Right      : Fragment;
      Ok         : out Boolean)
   is
      Added : Boolean;
   begin
      Ok := True;
      Patch_To (Expression, Left, Right.Start);
      Left.Out_Count := 0;
      for I in 1 .. Right.Out_Count loop
         Append_Out (Left, Right.Outs (I), Added);
         if not Added then
            Ok := False;
            return;
         end if;
      end loop;
   end Concat;

   procedure Append_Alternative
     (Expression   : in out Regexp;
      Alternatives : in out Fragment;
      Branch       : Fragment;
      Max_States   : Positive;
      Ok           : out Boolean)
   is
      Split  : State_Index;
      Result : Fragment;
   begin
      New_State (Expression, Node_Split, Max_States, Split);
      if Split = No_State then
         Ok := False;
         return;
      end if;

      Expression.States (Positive (Split)).Out_1 := Alternatives.Start;
      Expression.States (Positive (Split)).Out_2 := Branch.Start;
      Result := (Start => Split, Outs => [others => <>], Out_Count => 0);
      Append_Outs (Result, Alternatives, Ok);
      if Ok then
         Append_Outs (Result, Branch, Ok);
      end if;

      if Ok then
         Alternatives := Result;
      end if;
   end Append_Alternative;

   procedure Epsilon_Fragment
     (Expression : in out Regexp;
      Max_States : Positive;
      Frag       : out Fragment;
      Ok         : out Boolean)
   is
      Split : State_Index;
   begin
      Frag := (others => <>);
      New_State (Expression, Node_Split, Max_States, Split);
      if Split = No_State then
         Ok := False;
         return;
      end if;

      Frag := (Start => Split, Outs => [others => <>], Out_Count => 1);
      Frag.Outs (1) := (State => Split, Field => Patch_Out_1);
      Ok := True;
   end Epsilon_Fragment;

   procedure Clone_Fragment
     (Expression  : in out Regexp;
      Source      : Fragment;
      First_State : Positive;
      Last_State  : Natural;
      Max_States  : Positive;
      Result      : out Fragment;
      Ok          : out Boolean)
   is
      Map : array (Positive range 1 .. Default_Max_States) of State_Index := [others => No_State];

      function Remap (State : State_Index) return State_Index is
      begin
         if State = No_State then
            return No_State;
         elsif Positive (State) >= First_State and then Positive (State) <= Last_State then
            return Map (Positive (State));
         else
            return State;
         end if;
      end Remap;

      New_Index : State_Index;
   begin
      Result := (others => <>);
      Ok := False;

      if Last_State < First_State then
         return;
      end if;

      for I in First_State .. Last_State loop
         New_State (Expression, Expression.States (I).Kind, Max_States, New_Index);
         if New_Index = No_State then
            return;
         end if;
         Map (I) := New_Index;
         Expression.States (Positive (New_Index)) := Expression.States (I);
      end loop;

      for I in First_State .. Last_State loop
         New_Index := Map (I);
         Expression.States (Positive (New_Index)).Out_1 := Remap (Expression.States (I).Out_1);
         Expression.States (Positive (New_Index)).Out_2 := Remap (Expression.States (I).Out_2);
      end loop;

      Result := Source;
      Result.Start := Remap (Source.Start);
      for I in 1 .. Source.Out_Count loop
         Result.Outs (I).State := Remap (Source.Outs (I).State);
      end loop;

      for I in 1 .. Result.Out_Count loop
         if Result.Outs (I).State /= No_State then
            case Result.Outs (I).Field is
               when Patch_Out_1 =>
                  Expression.States (Positive (Result.Outs (I).State)).Out_1 := No_State;
               when Patch_Out_2 =>
                  Expression.States (Positive (Result.Outs (I).State)).Out_2 := No_State;
            end case;
         end if;
      end loop;
      Ok := True;
   end Clone_Fragment;

   procedure Quantify
     (Expression : in out Regexp;
      Frag       : Fragment;
      Quantifier : Character;
      Max_States : Positive;
      Ok         : out Boolean;
      Result     : out Fragment)
   is
      Split : State_Index;
   begin
      case Quantifier is
         when '*' =>
            New_State (Expression, Node_Split, Max_States, Split);
            if Split = No_State then
               Ok := False;
               Result := (others => <>);
               return;
            end if;
            Expression.States (Positive (Split)).Out_1 := Frag.Start;
            Patch_To (Expression, Frag, Split);
            Result := (Start => Split, Outs => [others => <>], Out_Count => 1);
            Result.Outs (1) := (State => Split, Field => Patch_Out_2);
            Ok := True;
            return;

         when '+' =>
            New_State (Expression, Node_Split, Max_States, Split);
            if Split = No_State then
               Ok := False;
               Result := (others => <>);
               return;
            end if;
            Expression.States (Positive (Split)).Out_1 := Frag.Start;
            Patch_To (Expression, Frag, Split);
            Result := (Start => Frag.Start, Outs => [others => <>], Out_Count => 1);
            Result.Outs (1) := (State => Split, Field => Patch_Out_2);
            Ok := True;
            return;

         when '?' =>
            New_State (Expression, Node_Split, Max_States, Split);
            if Split = No_State then
               Ok := False;
               Result := (others => <>);
               return;
            end if;
            Expression.States (Positive (Split)).Out_1 := Frag.Start;
            Result := (Start => Split, Outs => [others => <>], Out_Count => 0);
            Append_Outs (Result, Frag, Ok);
            if Ok then
               Append_Out (Result, (State => Split, Field => Patch_Out_2), Ok);
            end if;
            return;

         when others =>
            Ok := False;
            Result := (others => <>);
            return;
      end case;
   end Quantify;

   procedure Parse_Bounded_Repeat
     (Pattern   : String;
      Pos       : in out Natural;
      Minimum   : out Natural;
      Maximum   : out Natural;
      Unbounded : out Boolean;
      Status    : out Compile_Status;
      Offset    : out Natural;
      Good      : out Boolean)
      with Pre => Pos >= Nat (Pattern'First)
                  and then Pos <= Nat (Pattern'Last)
                  and then Pattern'Last < Positive'Last,
           Post => Pos > Pos'Old
   is
      Limit      : constant Natural := Default_Max_States + 1;
      First_Pos  : constant Natural := Nat (Pattern'First);
      Last_Pos   : constant Natural := Nat (Pattern'Last);
      After_Last : constant Natural := Last_Pos + 1;
      Have_Min : Boolean;
      Have_Max : Boolean;
      Brace    : constant Natural := Pos;
   begin
      Minimum := 0;
      Maximum := 0;
      Unbounded := False;
      Status := Compile_Ok;
      Offset := 0;
      Good := False;

      Advance (Pos);
      pragma Assert (Pos > Brace);
      Have_Min := False;
      while Pos <= Last_Pos
        and then Pattern (Positive (Pos)) in '0' .. '9'
      loop
         pragma Loop_Invariant (Pos >= First_Pos);
         pragma Loop_Invariant (Pos > Brace);
         pragma Loop_Invariant (Pos <= After_Last);
         pragma Loop_Invariant (Minimum <= Limit);
         pragma Loop_Variant (Increases => Pos);

         Have_Min := True;
         if Minimum < Limit then
            Minimum := Minimum * 10 + Character'Pos (Pattern (Positive (Pos))) - Character'Pos ('0');
            if Minimum > Limit then
               Minimum := Limit;
            end if;
         end if;
         Advance (Pos);
      end loop;

      if not Have_Min then
         Status := Invalid_Quantifier;
         Offset := Brace;
         return;
      end if;

      if Pos > Last_Pos then
         Status := Invalid_Quantifier;
         Offset := Brace;
         return;
      end if;

      if Pattern (Positive (Pos)) = '}' then
         Maximum := Minimum;
         Advance (Pos);
         Good := True;
         return;
      elsif Pattern (Positive (Pos)) /= ',' then
         Status := Invalid_Quantifier;
         Offset := Pos;
         return;
      end if;

      Advance (Pos);
      pragma Assert (Pos > Brace);
      Have_Max := False;
      while Pos <= Last_Pos
        and then Pattern (Positive (Pos)) in '0' .. '9'
      loop
         pragma Loop_Invariant (Pos >= First_Pos);
         pragma Loop_Invariant (Pos > Brace);
         pragma Loop_Invariant (Pos <= After_Last);
         pragma Loop_Invariant (Maximum <= Limit);
         pragma Loop_Variant (Increases => Pos);

         Have_Max := True;
         if Maximum < Limit then
            Maximum := Maximum * 10 + Character'Pos (Pattern (Positive (Pos))) - Character'Pos ('0');
            if Maximum > Limit then
               Maximum := Limit;
            end if;
         end if;
         Advance (Pos);
      end loop;

      if Pos > Last_Pos or else Pattern (Positive (Pos)) /= '}' then
         Status := Invalid_Quantifier;
         Offset := Brace;
         return;
      end if;

      Advance (Pos);
      if not Have_Max then
         Unbounded := True;
         Maximum := Minimum;
      elsif Maximum < Minimum then
         Status := Invalid_Quantifier;
         Offset := Pos - 1;
         return;
      end if;

      Good := True;
   end Parse_Bounded_Repeat;

   procedure Build_Bounded_Repeat
     (Expression : in out Regexp;
      Kind       : Node_Kind;
      Ch         : Character;
      Class      : Character_Class;
      Minimum    : Natural;
      Maximum    : Natural;
      Unbounded  : Boolean;
      Max_States : Positive;
      Result     : out Fragment;
      Ok         : out Boolean;
      Modes      : Scoped_Options := (others => Option_Inherit))
   is
      Next_Atom : Fragment;
      Optional  : Fragment;
   begin
      Ok := True;

      if Minimum = 0 then
         Epsilon_Fragment (Expression, Max_States, Result, Ok);
         if not Ok then
            return;
         end if;
      else
         Atom_Fragment (Expression, Kind, Max_States, Result, Ch, Class, Modes);
         if Result.Start = No_State then
            Ok := False;
            return;
         end if;

         for I in 2 .. Minimum loop
            pragma Loop_Invariant (Result.Start /= No_State);
            Atom_Fragment (Expression, Kind, Max_States, Next_Atom, Ch, Class, Modes);
            if Next_Atom.Start = No_State then
               Ok := False;
               return;
            end if;
            Concat (Expression, Result, Next_Atom, Ok);
            if not Ok then
               return;
            end if;
         end loop;
      end if;

      if Unbounded then
         Atom_Fragment (Expression, Kind, Max_States, Next_Atom, Ch, Class, Modes);
         if Next_Atom.Start = No_State then
            Ok := False;
            return;
         end if;
         Quantify (Expression, Next_Atom, '*', Max_States, Ok, Optional);
         if Ok then
            Concat (Expression, Result, Optional, Ok);
         end if;
      else
         for I in 1 .. Maximum - Minimum loop
            pragma Loop_Invariant (Result.Start /= No_State);
            Atom_Fragment (Expression, Kind, Max_States, Next_Atom, Ch, Class, Modes);
            if Next_Atom.Start = No_State then
               Ok := False;
               return;
            end if;
            Quantify (Expression, Next_Atom, '?', Max_States, Ok, Optional);
            if not Ok then
               return;
            end if;
            Concat (Expression, Result, Optional, Ok);
            if not Ok then
               return;
            end if;
         end loop;
      end if;
   end Build_Bounded_Repeat;

   procedure Build_Fragment_Bounded_Repeat
     (Expression  : in out Regexp;
      Base        : Fragment;
      First_State : Positive;
      Last_State  : Natural;
      Minimum     : Natural;
      Maximum     : Natural;
      Unbounded   : Boolean;
      Max_States  : Positive;
      Result      : out Fragment;
      Ok          : out Boolean)
   is
      Next_Atom : Fragment;
      Optional  : Fragment;
   begin
      Ok := True;

      if Minimum = 0 then
         Epsilon_Fragment (Expression, Max_States, Result, Ok);
         if not Ok then
            return;
         end if;
      else
         Result := Base;
         for I in 2 .. Minimum loop
            pragma Loop_Invariant (Result.Start /= No_State);
            Clone_Fragment (Expression, Base, First_State, Last_State, Max_States, Next_Atom, Ok);
            if not Ok then
               return;
            end if;
            Concat (Expression, Result, Next_Atom, Ok);
            if not Ok then
               return;
            end if;
         end loop;
      end if;

      if Unbounded then
         Clone_Fragment (Expression, Base, First_State, Last_State, Max_States, Next_Atom, Ok);
         if not Ok then
            return;
         end if;
         Quantify (Expression, Next_Atom, '*', Max_States, Ok, Optional);
         if Ok then
            Concat (Expression, Result, Optional, Ok);
         end if;
      else
         for I in 1 .. Maximum - Minimum loop
            pragma Loop_Invariant (Result.Start /= No_State);
            Clone_Fragment (Expression, Base, First_State, Last_State, Max_States, Next_Atom, Ok);
            if not Ok then
               return;
            end if;
            Quantify (Expression, Next_Atom, '?', Max_States, Ok, Optional);
            if not Ok then
               return;
            end if;
            Concat (Expression, Result, Optional, Ok);
            if not Ok then
               return;
            end if;
         end loop;
      end if;
   end Build_Fragment_Bounded_Repeat;

   procedure Escape_Class
     (Escaped : Character;
      Class   : out Character_Class;
      Single  : out Boolean;
      Ch      : out Character;
      Good    : out Boolean)
   is
   begin
      Class := (others => <>);
      Single := False;
      Ch := Character'Val (0);
      Good := True;

      case Escaped is
         when 'd' =>
            Add_Digit (Class);
         when 'D' =>
            Add_Digit (Class);
            Class.Negated := True;
         when 'w' =>
            Add_Word (Class);
         when 'W' =>
            Add_Word (Class);
            Class.Negated := True;
         when 's' =>
            Add_Whitespace (Class);
         when 'S' =>
            Add_Whitespace (Class);
            Class.Negated := True;
         when 'h' =>
            Add_Horizontal_Whitespace (Class);
         when 'H' =>
            Add_Horizontal_Whitespace (Class);
            Class.Negated := True;
         when 'v' =>
            Add_Vertical_Whitespace (Class);
         when 'V' =>
            Add_Vertical_Whitespace (Class);
            Class.Negated := True;
         when 'b' =>
            Class.Members (Character'Val (8)) := True;
         when '.' | '*' | '+' | '?' | '(' | ')' | '[' | ']' | '{' | '}' | '\' | '^' | '$' | '-' | '|' =>
            Ch := Escaped;
            Single := True;
            Class.Members (Ch) := True;
         when others =>
            Good := False;
            return;
      end case;

   end Escape_Class;

   procedure Parse_Class
     (Pattern : String;
      Pos     : in out Natural;
      Class   : out Character_Class;
      Status  : out Compile_Status;
      Offset  : out Natural;
      Good    : out Boolean;
      Mode    : Character_Mode_Type := ASCII_Mode)
      with Pre  => Pos >= Nat (Pattern'First)
                   and then Pos <= Nat (Pattern'Last)
                   and then Pattern'Last < Positive'Last,
           Post => Pos >= Pos'Old and then Pos <= Nat (Pattern'Last) + 1
   is
      procedure Read_Item
        (Item   : out Character_Class;
         Single : out Boolean;
         Ch     : out Character;
         Code   : out Code_Point;
         Good   : out Boolean)
      with Pre  => Pos >= Nat (Pattern'First)
                   and then Pos <= Nat (Pattern'Last)
                   and then Pattern'Last < Positive'Last,
           Post => Pos >= Pos'Old
                   and then Pos <= Nat (Pattern'Last) + 1
                   and then (if Good then Pos > Pos'Old)
      is
         Matched_Posix : Boolean;

         procedure Apply_Posix_Class
           (Name   : String;
            Target : in out Character_Class;
            Ok     : out Boolean)
         is
         begin
            Ok := True;
            if Name = "alnum" then
               Add_Alpha (Target);
               Add_Digit (Target);
            elsif Name = "alpha" then
               Add_Alpha (Target);
            elsif Name = "blank" then
               Add_Blank (Target);
            elsif Name = "cntrl" then
               Add_Cntrl (Target);
            elsif Name = "digit" then
               Add_Digit (Target);
            elsif Name = "graph" then
               Add_Graph (Target);
            elsif Name = "lower" then
               Add_Lower (Target);
            elsif Name = "print" then
               Add_Print (Target);
            elsif Name = "punct" then
               Add_Punct (Target);
            elsif Name = "space" then
               Add_Whitespace (Target);
            elsif Name = "upper" then
               Add_Upper (Target);
            elsif Name = "word" then
               Add_Word (Target);
            elsif Name = "xdigit" then
               Add_Xdigit (Target);
            else
               Ok := False;
            end if;
         end Apply_Posix_Class;

         --  A procedure, not a function: it advances Pos and sets Item/Single/Good, and
         --  SPARK forbids a function with output globals. Matched reports whether the
         --  cursor was on a POSIX class like [:alpha:].
         procedure Try_Posix_Class (Matched : out Boolean) is
            Name_First : Natural;
            Name_Last  : Natural;
         begin
            Matched := False;
            if Pos + 3 > Nat (Pattern'Last)
              or else Pattern (Positive (Pos)) /= '['
              or else Pattern (Positive (Pos + 1)) /= ':'
            then
               return;
            end if;

            Name_First := Pos + 2;
            Name_Last := Name_First;
            while Name_Last + 1 <= Nat (Pattern'Last)
              and then not
                (Pattern (Positive (Name_Last)) = ':'
                 and then Pattern (Positive (Name_Last + 1)) = ']')
            loop
               pragma Loop_Variant (Increases => Name_Last);
               Name_Last := Name_Last + 1;
            end loop;

            if Name_Last + 1 > Nat (Pattern'Last) or else Name_Last = Name_First then
               return;
            end if;

            Item := (others => <>);
            Apply_Posix_Class (Pattern (Positive (Name_First) .. Positive (Name_Last - 1)), Item, Good);
            if not Good then
               return;
            end if;

            Single := False;
            Pos := Name_Last + 2;
            Good := True;
            Matched := True;
         end Try_Posix_Class;
      begin
         Item := (others => <>);
         Single := False;
         Ch := Character'Val (0);
         Code := 0;
         Good := False;

         if Pos < Positive'First or else Pos > Nat (Pattern'Last) then
            return;
         end if;

         Try_Posix_Class (Matched_Posix);
         if Matched_Posix then
            return;
         elsif Pattern (Positive (Pos)) in 'p' | 'P' then
            Parse_Unicode_Property (Pattern, Pos, Item, Status, Offset, Good);
            if not Good then
               return;
            end if;
            Single := False;
         elsif Pattern (Positive (Pos)) = '\' then
            Advance (Pos);
            if Pos > Nat (Pattern'Last) then
               Status := Invalid_Escape;
               Offset := (if Pos = 0 then 0 else Pos - 1);
               return;
            end if;
            Escape_Class (Pattern (Positive (Pos)), Item, Single, Ch, Good);
            if not Good then
               Status := Invalid_Escape;
               Offset := Pos;
               return;
            end if;
            Code := Code_Point (Character'Pos (Ch));
            Advance (Pos);
         elsif Mode = UTF_8_Mode
           and then Character'Pos (Pattern (Positive (Pos))) >= 16#80#
         then
            --  A multibyte class member: read the whole code point.
            declare
               CP  : Code_Point;
               Len : Positive;
            begin
               Decode_Utf8 (Pattern, Positive (Pos), CP, Len);
               Ch := Pattern (Positive (Pos));
               Code := CP;
               Single := True;
               Add_Code_Range (Item, CP, CP);
               Pos := Pos + Len;
               Good := True;
            end;
         else
            Ch := Pattern (Positive (Pos));
            Code := Code_Point (Character'Pos (Ch));
            Single := True;
            Item.Members (Ch) := True;
            Advance (Pos);
            Good := True;
         end if;
      end Read_Item;

      Item       : Character_Class;
      Term       : Character_Class;
      Range_End  : Character_Class;
      Single     : Boolean;
      End_Single : Boolean;
      Ch         : Character;
      End_Ch     : Character;
      Code_Start : Code_Point;
      Code_End   : Code_Point;
      Item_Good  : Boolean;
      Had_Item   : Boolean := False;
      Negated    : Boolean := False;
      Enter_Pos  : constant Natural := Pos;   --  entry Pos (= Pos'Old), for the Post
   begin
      Class := (others => <>);
      Status := Compile_Ok;
      Offset := 0;
      Good := False;

      Advance (Pos);
      if Pos <= Nat (Pattern'Last) and then Pattern (Positive (Pos)) = '^' then
         Negated := True;
         Advance (Pos);
      end if;

      while Pos <= Nat (Pattern'Last) and then Pattern (Positive (Pos)) /= ']' loop
         pragma Loop_Invariant (Pos >= Nat (Pattern'First));
         pragma Loop_Invariant (Pos >= Positive'First);
         pragma Loop_Invariant (Pos >= Enter_Pos);
         pragma Loop_Invariant (Pos <= Nat (Pattern'Last) + 1);
         pragma Loop_Variant (Increases => Pos);

         Read_Item (Item, Single, Ch, Code_Start, Item_Good);
         if not Item_Good then
            return;
         end if;

         Term := Item;
         if Pos <= Nat (Pattern'Last)
           and then Pattern (Positive (Pos)) = '-'
           and then Pos < Nat (Pattern'Last)
           and then Pattern (Positive (Pos + 1)) /= ']'
           and then not
             (Pos <= Nat (Pattern'Last)
              and then Nat (Pattern'Last) - Pos >= 2
              and then Pattern (Positive (Pos + 1)) = '-'
              and then Pattern (Positive (Pos + 2)) = '[')
         then
            if not Single then
               Status := Invalid_Class_Range;
               Offset := Pos;
               return;
            end if;

            Advance (Pos);
            Read_Item (Range_End, End_Single, End_Ch, Code_End, Item_Good);
            if not Item_Good then
               return;
            end if;
            if Range_End.Negated or else not End_Single or else Code_Start > Code_End then
               Status := Invalid_Class_Range;
               Offset := (if Pos = 0 then 0 else Pos - 1);
               return;
            end if;
            Term := (others => <>);
            Add_Code_Range (Term, Code_Start, Code_End);
         end if;

         Merge (Class, Term);
         Had_Item := True;

         if Pos <= Nat (Pattern'Last)
           and then Nat (Pattern'Last) - Pos >= 2
           and then Pattern (Positive (Pos)) = '&'
           and then Pattern (Positive (Pos + 1)) = '&'
           and then Pattern (Positive (Pos + 2)) = '['
         then
            Pos := Pos + 2;
            Parse_Class (Pattern, Pos, Range_End, Status, Offset, Item_Good, Mode);
            if not Item_Good then
               return;
            end if;
            Intersect (Class, Range_End);
         elsif Pos <= Nat (Pattern'Last)
           and then Nat (Pattern'Last) - Pos >= 2
           and then Pattern (Positive (Pos)) = '-'
           and then Pattern (Positive (Pos + 1)) = '-'
           and then Pattern (Positive (Pos + 2)) = '['
         then
            Pos := Pos + 2;
            Parse_Class (Pattern, Pos, Range_End, Status, Offset, Item_Good, Mode);
            if not Item_Good then
               return;
            end if;
            Subtract (Class, Range_End);
         else
            null;
         end if;
      end loop;

      if Pos > Nat (Pattern'Last) then
         Status := Unterminated_Class;
         Offset := Nat (Pattern'Last);
         return;
      end if;

      if not Had_Item then
         Status := Empty_Class;
         Offset := Pos;
         return;
      end if;

      Class.Negated := Negated;
      Advance (Pos);
      Good := True;
      return;
   end Parse_Class;

   procedure Escape_Atom
     (Escaped : Character;
      Kind    : out Node_Kind;
      Ch      : out Character;
      Class   : out Character_Class;
      Good    : out Boolean)
   is
   begin
      Kind := Node_Invalid;
      Ch := Character'Val (0);
      Class := (others => <>);
      Good := True;

      case Escaped is
         when 'd' =>
            Kind := Node_Class;
            Add_Digit (Class);
         when 'D' =>
            Kind := Node_Class;
            Add_Digit (Class);
            Class.Negated := True;
         when 'w' =>
            Kind := Node_Class;
            Add_Word (Class);
         when 'W' =>
            Kind := Node_Class;
            Add_Word (Class);
            Class.Negated := True;
         when 's' =>
            Kind := Node_Class;
            Add_Whitespace (Class);
         when 'S' =>
            Kind := Node_Class;
            Add_Whitespace (Class);
            Class.Negated := True;
         when 'h' =>
            Kind := Node_Class;
            Add_Horizontal_Whitespace (Class);
         when 'H' =>
            Kind := Node_Class;
            Add_Horizontal_Whitespace (Class);
            Class.Negated := True;
         when 'v' =>
            Kind := Node_Class;
            Add_Vertical_Whitespace (Class);
         when 'V' =>
            Kind := Node_Class;
            Add_Vertical_Whitespace (Class);
            Class.Negated := True;
         when 'b' =>
            Kind := Node_Word_Boundary;
         when 'B' =>
            Kind := Node_Not_Word_Boundary;
         when '.' | '*' | '+' | '?' | '(' | ')' | '[' | ']' | '{' | '}' | '\' | '^' | '$' | '|' =>
            Kind := Node_Char;
            Ch := Escaped;
         when others =>
            Good := False;
            return;
      end case;

   end Escape_Atom;

   procedure Store_Source
     (Expression : in out Regexp;
      Source     : String;
      Kind       : Pattern_Source_Kind)
   is
      Limit : constant Natural := Natural'Min (Source'Length, Default_Max_Pattern_Length);
   begin
      Expression.Source_Kind := Kind;
      Expression.Source_Length := Limit;
      Expression.Source_Pattern := [others => Character'Val (0)];
      for I in 1 .. Limit loop
         Expression.Source_Pattern (I) := Source (Source'First + I - 1);
      end loop;
   end Store_Source;

   function Compile
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States;
      Character_Mode     : Character_Mode_Type := ASCII_Mode)
      return Compile_Result
   is
      Result : Compile_Result;
      Pos    : Natural := Nat (Pattern'First);
      Match  : State_Index;

      procedure Parse_Expression
        (Stop_At_Close : Boolean;
         Modes         : Scoped_Options;
         Expr          : out Fragment;
         Closing_Found : out Boolean;
         Status        : out Compile_Status;
         Offset        : out Natural;
         Good          : out Boolean)
      is
         Have_Frag        : Boolean := False;
         Have_Alternative : Boolean := False;
         Current          : Fragment;
         Alternatives     : Fragment;
         Atom             : Fragment;
         Atom_First_State : Positive := 1;
         Atom_Last_State  : Natural := 0;
         Kind             : Node_Kind := Node_Invalid;
         Ch               : Character;
         Class            : Character_Class;
         Local_Status     : Compile_Status;
         Local_Offset     : Natural;
         Ok               : Boolean;
         Quantified       : Fragment;
         Repeated         : Fragment;
         Parsed_Atom      : Boolean;
         Minimum          : Natural;
         Maximum          : Natural;
         Unbounded        : Boolean;
         Group_Closed     : Boolean;
         Capture_Start    : Fragment;
         Capture_End      : Fragment;
         Capture_Number   : Natural;
         Capture_Name_First : Natural;
         Capture_Name_Last  : Natural;
         Name_Pos          : Natural;
         Named_Capture     : Boolean;
         Group_Start       : Natural;
         Lookahead_Atom    : Fragment;
         Lookbehind_Fixed  : Boolean;
         Saved_Capture_Count : Natural;
         Saved_Capture_Names : Capture_Name_Array;
         Saved_Capture_Name_Lengths : Capture_Name_Length_Array;
         Option_Pos       : Natural;
         Option_Modes     : Scoped_Options;
         Option_Negating  : Boolean;
         Option_Had_Item  : Boolean;
         Option_Is_Group  : Boolean;
         Backref_Number   : Natural;
         Backref_Name_First : Natural;
         Backref_Name_Last  : Natural;
      begin
         Expr := (others => <>);
         Closing_Found := False;
         Status := Compile_Ok;
         Offset := 0;
         Good := False;

         while Pos <= Nat (Pattern'Last) loop
            pragma Loop_Invariant (Pos >= Nat (Pattern'First));
            pragma Loop_Invariant (Pos >= Positive'First);
            pragma Loop_Invariant (Pos <= Nat (Pattern'Last));
            pragma Loop_Variant (Increases => Pos);

            Ch := Character'Val (0);
            Class := (others => <>);
            Parsed_Atom := True;
            Atom_First_State := Result.Expression.State_Count + 1;
            Named_Capture := False;
            Capture_Name_First := 0;
            Capture_Name_Last := 0;

            case Pattern (Positive (Pos)) is
               when ')' =>
                  if Stop_At_Close then
                     Closing_Found := True;
                     Advance (Pos);
                     exit;
                  end if;
                  Status := Unsupported_Syntax;
                  Offset := Relative_Offset (Pattern'First, Pos);
                  return;

               when '*' | '+' | '?' =>
                  Status := Quantifier_Without_Atom;
                  Offset := Relative_Offset (Pattern'First, Pos);
                  return;

               when '|' =>
                  if not Have_Frag then
                     Epsilon_Fragment (Result.Expression, Max_States, Current, Ok);
                     if not Ok then
                        Status := Too_Many_States;
                        Offset := Relative_Offset (Pattern'First, Pos);
                        return;
                     end if;
                     Have_Frag := True;
                  end if;

                  if Have_Alternative then
                     Append_Alternative (Result.Expression, Alternatives, Current, Max_States, Ok);
                     if not Ok then
                        Status := Too_Many_States;
                        Offset := Relative_Offset (Pattern'First, Pos);
                        return;
                     end if;
                  else
                     Alternatives := Current;
                     Have_Alternative := True;
                  end if;
                  Current := (others => <>);
                  Have_Frag := False;
                  Advance (Pos);
                  Parsed_Atom := False;

               when '(' =>
                  Group_Start := Pos;
                  if Pos + 2 <= Nat (Pattern'Last)
                    and then Pattern (Positive (Pos + 1)) = '?'
                    and then Pattern (Positive (Pos + 2)) = ':'
                  then
                     Pos := Pos + 3;
                     Parse_Expression (True, Modes, Atom, Group_Closed, Status, Offset, Ok);
                     if not Ok then
                        return;
                     elsif not Group_Closed then
                        Status := Unsupported_Syntax;
                        Offset := Pattern'Length;
                        return;
                     end if;
                  elsif Pos + 2 <= Nat (Pattern'Last)
                    and then Pattern (Positive (Pos + 1)) = '?'
                    and then Pattern (Positive (Pos + 2)) = '>'
                  then
                     if Result.Expression.Capture_Count /= 0 then
                        Status := Unsupported_Syntax;
                        Offset := Relative_Offset (Pattern'First, Group_Start);
                        return;
                     end if;
                     Pos := Pos + 3;
                     Parse_Expression (True, Modes, Atom, Group_Closed, Status, Offset, Ok);
                     if not Ok then
                        return;
                     elsif not Group_Closed then
                        Status := Unsupported_Syntax;
                        Offset := Pattern'Length;
                        return;
                     elsif not Atomic_Subpattern_Supported
                         (Result.Expression, Atom_First_State, Result.Expression.State_Count)
                     then
                        Status := Unsupported_Syntax;
                        Offset := Relative_Offset (Pattern'First, Group_Start);
                        return;
                     end if;

                     Atomic_Fragment (Result.Expression, Atom, Max_States, Quantified);
                     Atom := Quantified;
                     if Atom.Start = No_State then
                        Status := Too_Many_States;
                        Offset := Relative_Offset (Pattern'First, Pos);
                        return;
                     end if;
                  elsif Pos + 2 <= Nat (Pattern'Last)
                    and then Pattern (Positive (Pos + 1)) = '?'
                    and then Pattern (Positive (Pos + 2)) in '=' | '!'
                  then
                     declare
                        Is_Positive : constant Boolean := Pattern (Positive (Pos + 2)) = '=';
                     begin
                        Saved_Capture_Count := Result.Expression.Capture_Count;
                        Saved_Capture_Names := Result.Expression.Capture_Names;
                        Saved_Capture_Name_Lengths := Result.Expression.Capture_Name_Lengths;
                        Pos := Pos + 3;
                        Parse_Expression (True, Modes, Lookahead_Atom, Group_Closed, Status, Offset, Ok);
                        if not Ok then
                           return;
                        elsif not Group_Closed then
                           Status := Unsupported_Syntax;
                           Offset := Pattern'Length;
                           return;
                        end if;

                        Result.Expression.Capture_Count := Saved_Capture_Count;
                        Result.Expression.Capture_Names := Saved_Capture_Names;
                        Result.Expression.Capture_Name_Lengths := Saved_Capture_Name_Lengths;

                        Lookahead_Fragment
                          (Result.Expression,
                           Is_Positive,
                           Lookahead_Atom,
                           Max_States,
                           Atom);
                        if Atom.Start = No_State then
                           Status := Too_Many_States;
                           Offset := Relative_Offset (Pattern'First, Pos);
                           return;
                        end if;
                     end;
                  elsif Pos + 3 <= Nat (Pattern'Last)
                    and then Pattern (Positive (Pos + 1)) = '?'
                    and then Pattern (Positive (Pos + 2)) = '<'
                    and then Pattern (Positive (Pos + 3)) in '=' | '!'
                  then
                     declare
                        Is_Positive : constant Boolean := Pattern (Positive (Pos + 3)) = '=';
                     begin
                        Saved_Capture_Count := Result.Expression.Capture_Count;
                        Saved_Capture_Names := Result.Expression.Capture_Names;
                        Saved_Capture_Name_Lengths := Result.Expression.Capture_Name_Lengths;
                        Pos := Pos + 4;
                        Parse_Expression (True, Modes, Lookahead_Atom, Group_Closed, Status, Offset, Ok);
                        if not Ok then
                           return;
                        elsif not Group_Closed then
                           Status := Unsupported_Syntax;
                           Offset := Pattern'Length;
                           return;
                        end if;

                        Result.Expression.Capture_Count := Saved_Capture_Count;
                        Result.Expression.Capture_Names := Saved_Capture_Names;
                        Result.Expression.Capture_Name_Lengths := Saved_Capture_Name_Lengths;

                        Lookbehind_Fragment
                          (Result.Expression,
                           Is_Positive,
                           Lookahead_Atom,
                           Max_States,
                           Atom,
                           Lookbehind_Fixed);
                        if Atom.Start = No_State then
                           Status := (if Lookbehind_Fixed then Too_Many_States else Unsupported_Syntax);
                           Offset := Relative_Offset (Pattern'First, Group_Start);
                           return;
                        end if;
                     end;
                  elsif Pos + 2 <= Nat (Pattern'Last)
                    and then Pattern (Positive (Pos + 1)) = '?'
                    and then Pattern (Positive (Pos + 2)) in 'i' | 'm' | 's' | '-'
                  then
                     Option_Pos := Pos + 2;
                     Option_Modes := Modes;
                     Option_Negating := False;
                     Option_Had_Item := False;
                     Option_Is_Group := False;

                     while Option_Pos <= Nat (Pattern'Last) loop
                        pragma Loop_Invariant (Option_Pos >= Nat (Pattern'First));
                        pragma Loop_Invariant (Option_Pos <= Nat (Pattern'Last) + 1);
                        pragma Loop_Variant (Increases => Option_Pos);

                        case Pattern (Positive (Option_Pos)) is
                           when 'i' =>
                              Option_Modes.Case_Sensitive :=
                                (if Option_Negating then Option_On else Option_Off);
                              Option_Had_Item := True;
                           when 'm' =>
                              Option_Modes.Multiline_Anchors :=
                                (if Option_Negating then Option_Off else Option_On);
                              Option_Had_Item := True;
                           when 's' =>
                              Option_Modes.Dot_Matches_Newline :=
                                (if Option_Negating then Option_Off else Option_On);
                              Option_Had_Item := True;
                           when '-' =>
                              if Option_Negating then
                                 exit;
                              end if;
                              Option_Negating := True;
                           when ':' =>
                              Option_Is_Group := Option_Had_Item;
                              exit;
                           when others =>
                              exit;
                        end case;

                        Advance (Option_Pos);
                     end loop;

                     if not Option_Is_Group then
                        Status := Unsupported_Syntax;
                        Offset := Relative_Offset (Pattern'First, Group_Start);
                        return;
                     end if;

                     Pos := Option_Pos + 1;
                     Parse_Expression (True, Option_Modes, Atom, Group_Closed, Status, Offset, Ok);
                     if not Ok then
                        return;
                     elsif not Group_Closed then
                        Status := Unsupported_Syntax;
                        Offset := Pattern'Length;
                        return;
                     end if;
                  else
                     if Pos + 3 <= Nat (Pattern'Last)
                       and then Pattern (Positive (Pos + 1)) = '?'
                       and then Pattern (Positive (Pos + 2)) = '<'
                     then
                        Named_Capture := True;
                        Capture_Name_First := Pos + 3;
                        Name_Pos := Capture_Name_First;
                        if Name_Pos > Nat (Pattern'Last)
                          or else not Is_Capture_Name_Start (Pattern (Positive (Name_Pos)))
                        then
                           Status := Invalid_Capture_Name;
                           Offset := Relative_Offset (Pattern'First, Pos);
                           return;
                        end if;

                        while Name_Pos <= Nat (Pattern'Last)
                          and then Pattern (Positive (Name_Pos)) /= '>'
                        loop
                           pragma Loop_Variant (Increases => Name_Pos);

                           if Name_Pos - Capture_Name_First >= Max_Capture_Name_Length
                             or else not Is_Capture_Name_Char (Pattern (Positive (Name_Pos)))
                           then
                              Status := Invalid_Capture_Name;
                              Offset := Relative_Offset (Pattern'First, Name_Pos);
                              return;
                           end if;
                           Advance (Name_Pos);
                        end loop;

                        if Name_Pos > Nat (Pattern'Last) then
                           Status := Invalid_Capture_Name;
                           Offset := Relative_Offset (Pattern'First, Pos);
                           return;
                        end if;

                        Capture_Name_Last := Name_Pos - 1;
                        if Has_Capture_Name
                            (Result.Expression, Pattern (Positive (Capture_Name_First) .. Positive (Capture_Name_Last)))
                        then
                           Status := Duplicate_Capture_Name;
                           Offset := Relative_Offset (Pattern'First, Capture_Name_First);
                           return;
                        end if;
                        Pos := Name_Pos + 1;
                     else
                        Advance (Pos);
                     end if;

                     if Result.Expression.Capture_Count = Max_Captures then
                        Status := Too_Many_Captures;
                        Offset := Relative_Offset (Pattern'First, Group_Start);
                        return;
                     elsif Result.Expression.Has_Atomic then
                        Status := Unsupported_Syntax;
                        Offset := Relative_Offset (Pattern'First, Group_Start);
                        return;
                     end if;

                     Result.Expression.Capture_Count := Result.Expression.Capture_Count + 1;
                     Capture_Number := Result.Expression.Capture_Count;
                     if Named_Capture then
                        Store_Capture_Name
                          (Result.Expression,
                           Positive (Capture_Number),
                           Pattern (Positive (Capture_Name_First) .. Positive (Capture_Name_Last)));
                     end if;
                     Capture_Fragment
                       (Result.Expression,
                        Node_Capture_Start,
                        Positive (Capture_Number),
                        Max_States,
                        Capture_Start);
                     if Capture_Start.Start = No_State then
                        Status := Too_Many_States;
                        Offset := Relative_Offset (Pattern'First, Pos);
                        return;
                     end if;

                     Parse_Expression (True, Modes, Atom, Group_Closed, Status, Offset, Ok);
                     if not Ok then
                        return;
                     elsif not Group_Closed then
                        Status := Unsupported_Syntax;
                        Offset := Pattern'Length;
                        return;
                     end if;

                     Capture_Fragment
                       (Result.Expression,
                        Node_Capture_End,
                        Positive (Capture_Number),
                        Max_States,
                        Capture_End);
                     if Capture_End.Start = No_State then
                        Status := Too_Many_States;
                        Offset := Relative_Offset (Pattern'First, Pos);
                        return;
                     end if;

                     Concat (Result.Expression, Capture_Start, Atom, Ok);
                     if Ok then
                        Concat (Result.Expression, Capture_Start, Capture_End, Ok);
                     end if;
                     if not Ok then
                        Status := Too_Many_States;
                        Offset := Relative_Offset (Pattern'First, Pos);
                        return;
                     end if;
                     Atom := Capture_Start;
                  end if;

               when '{' | '}' =>
                  Status := Unsupported_Syntax;
                  Offset := Relative_Offset (Pattern'First, Pos);
                  return;

               when '.' =>
                  Kind := Node_Any;
                  Advance (Pos);
                  Atom_Fragment (Result.Expression, Kind, Max_States, Atom, Ch, Class, Modes);

               when '^' =>
                  Kind := Node_Start_Line;
                  Advance (Pos);
                  Atom_Fragment (Result.Expression, Kind, Max_States, Atom, Ch, Class, Modes);

               when '$' =>
                  Kind := Node_End_Line;
                  Advance (Pos);
                  Atom_Fragment (Result.Expression, Kind, Max_States, Atom, Ch, Class, Modes);

               when '[' =>
                  declare
                     Before_Class : constant Natural := Pos;
                  begin
                     Parse_Class (Pattern, Pos, Class, Local_Status, Local_Offset, Ok, Character_Mode);
                     if not Ok then
                        Status := Local_Status;
                        Offset := Relative_Offset (Pattern'First, Local_Offset);
                        return;
                     elsif Pos <= Before_Class then
                        Status := Invalid_Quantifier;
                        Offset := Relative_Offset (Pattern'First, Before_Class);
                        return;
                     end if;
                  end;
                  Kind := Node_Class;
                  Atom_Fragment (Result.Expression, Kind, Max_States, Atom, Ch, Class, Modes);

               when '\' =>
                  Advance (Pos);
                  if Pos > Nat (Pattern'Last) then
                     Status := Invalid_Escape;
                     Offset := Pattern'Length;
                     return;
                  end if;
                  if Pattern (Positive (Pos)) in '1' .. '9' then
                     Backref_Number := Character'Pos (Pattern (Positive (Pos))) - Character'Pos ('0');
                     if Backref_Number > Result.Expression.Capture_Count then
                        Status := Invalid_Escape;
                        Offset := Relative_Offset (Pattern'First, Pos);
                        return;
                     end if;
                     Advance (Pos);
                     Backreference_Fragment
                       (Result.Expression, Positive (Backref_Number), Max_States, Modes, Atom);
                  elsif Pattern (Positive (Pos)) = 'k'
                    and then Pos + 1 <= Nat (Pattern'Last)
                    and then Pattern (Positive (Pos + 1)) = '<'
                  then
                     Backref_Name_First := Pos + 2;
                     Backref_Name_Last := Backref_Name_First;
                     while Backref_Name_Last <= Nat (Pattern'Last)
                       and then Pattern (Positive (Backref_Name_Last)) /= '>'
                     loop
                        pragma Loop_Variant (Increases => Backref_Name_Last);
                        Advance (Backref_Name_Last);
                     end loop;

                     if Backref_Name_First > Nat (Pattern'Last)
                       or else Backref_Name_Last > Nat (Pattern'Last)
                       or else Backref_Name_Last = Backref_Name_First
                     then
                        Status := Invalid_Escape;
                        Offset := Relative_Offset (Pattern'First, Pos);
                        return;
                     end if;

                     Backref_Number :=
                       Capture_Name_Index
                         (Result.Expression,
                          Pattern (Positive (Backref_Name_First) .. Positive (Backref_Name_Last - 1)));
                     if Backref_Number = 0 then
                        Status := Invalid_Escape;
                        Offset := Relative_Offset (Pattern'First, Pos);
                        return;
                     end if;
                     Pos := Backref_Name_Last + 1;
                     Backreference_Fragment
                       (Result.Expression, Positive (Backref_Number), Max_States, Modes, Atom);
                  elsif Pattern (Positive (Pos)) in 'p' | 'P' then
                     Parse_Unicode_Property (Pattern, Pos, Class, Local_Status, Local_Offset, Ok);
                     if not Ok then
                        Status := Local_Status;
                        Offset := Relative_Offset (Pattern'First, Local_Offset);
                        return;
                     end if;
                     Kind := Node_Class;
                     Atom_Fragment (Result.Expression, Kind, Max_States, Atom, Ch, Class, Modes);
                  else
                     Escape_Atom (Pattern (Positive (Pos)), Kind, Ch, Class, Ok);
                     if not Ok then
                        Status := Invalid_Escape;
                        Offset := Relative_Offset (Pattern'First, Pos);
                        return;
                     end if;
                     Advance (Pos);
                     Atom_Fragment (Result.Expression, Kind, Max_States, Atom, Ch, Class, Modes);
                  end if;

               when others =>
                  if Character_Mode = UTF_8_Mode
                    and then Character'Pos (Pattern (Positive (Pos))) >= 16#80#
                  then
                     --  A multibyte literal must match a whole code point; a
                     --  lockstep-by-codepoint automaton cannot express it as a
                     --  sequence of byte Node_Char nodes, so emit a single-member
                     --  class node instead.
                     declare
                        CP  : Code_Point;
                        Len : Positive;
                     begin
                        Decode_Utf8 (Pattern, Positive (Pos), CP, Len);
                        Class := (others => <>);
                        Add_Code_Range (Class, CP, CP);
                        Pos := Pos + Len;
                        Atom_Fragment (Result.Expression, Node_Class, Max_States, Atom, Ch, Class, Modes);
                     end;
                  else
                     Kind := Node_Char;
                     Ch := Pattern (Positive (Pos));
                     Advance (Pos);
                     Atom_Fragment (Result.Expression, Kind, Max_States, Atom, Ch, Class, Modes);
                  end if;
            end case;

            if Parsed_Atom then
               if Atom.Start = No_State then
                  Status := Too_Many_States;
                  Offset := Relative_Offset (Pattern'First, Pos);
                  return;
               end if;

               Atom_Last_State := Result.Expression.State_Count;

               if Pos >= Positive'First
                 and then Pos <= Nat (Pattern'Last)
                 and then Pattern (Positive (Pos)) = '{'
               then
                  Parse_Bounded_Repeat (Pattern, Pos, Minimum, Maximum, Unbounded, Local_Status, Local_Offset, Ok);
                  if not Ok then
                     Status := Local_Status;
                     Offset := Relative_Offset (Pattern'First, Local_Offset);
                     return;
                  end if;

                  Build_Fragment_Bounded_Repeat
                    (Result.Expression,
                     Atom,
                     Atom_First_State,
                     Atom_Last_State,
                     Minimum,
                     Maximum,
                     Unbounded,
                     Max_States,
                     Repeated,
                     Ok);
                  if not Ok then
                     Status := Too_Many_States;
                     Offset := Relative_Offset (Pattern'First, Pos);
                     return;
                  end if;
                  Atom := Repeated;
                  if Pos >= Positive'First
                    and then Pos <= Nat (Pattern'Last)
                    and then Pattern (Positive (Pos)) = '?'
                  then
                     Result.Expression.Prefer_First_Match := True;
                     Advance (Pos);
                  elsif Pos >= Positive'First
                    and then Pos <= Nat (Pattern'Last)
                    and then Pattern (Positive (Pos)) = '+'
                  then
                     Advance (Pos);
                     if not Atomic_Subpattern_Supported
                         (Result.Expression, Atom_First_State, Result.Expression.State_Count)
                       or else Result.Expression.Capture_Count /= 0
                     then
                        Status := Unsupported_Syntax;
                        Offset := Relative_Offset (Pattern'First, Pos - 1);
                        return;
                     end if;
                     Atomic_Fragment (Result.Expression, Atom, Max_States, Quantified);
                     if Quantified.Start = No_State then
                        Status := Too_Many_States;
                        Offset := Relative_Offset (Pattern'First, Pos - 1);
                        return;
                     end if;
                     Atom := Quantified;
                  end if;

                  if Pos >= Positive'First
                    and then Pos <= Nat (Pattern'Last)
                    and then Pattern (Positive (Pos)) in '*' | '+' | '?' | '{'
                  then
                     Status := Invalid_Quantifier;
                     Offset := Relative_Offset (Pattern'First, Pos);
                     return;
                  end if;
               elsif Pos >= Positive'First
                 and then Pos <= Nat (Pattern'Last)
                 and then Pattern (Positive (Pos)) in '*' | '+' | '?'
               then
                  Quantify (Result.Expression, Atom, Pattern (Positive (Pos)), Max_States, Ok, Quantified);
                  Atom := Quantified;
                  if not Ok then
                     Status := Too_Many_States;
                     Offset := Relative_Offset (Pattern'First, Pos);
                     return;
                  end if;
                  Advance (Pos);
                  if Pos >= Positive'First
                    and then Pos <= Nat (Pattern'Last)
                    and then Pattern (Positive (Pos)) = '?'
                  then
                     Result.Expression.Prefer_First_Match := True;
                     Advance (Pos);
                  elsif Pos >= Positive'First
                    and then Pos <= Nat (Pattern'Last)
                    and then Pattern (Positive (Pos)) = '+'
                  then
                     Advance (Pos);
                     if not Atomic_Subpattern_Supported
                         (Result.Expression, Atom_First_State, Result.Expression.State_Count)
                       or else Result.Expression.Capture_Count /= 0
                     then
                        Status := Unsupported_Syntax;
                        Offset := Relative_Offset (Pattern'First, Pos - 1);
                        return;
                     end if;
                     Atomic_Fragment (Result.Expression, Atom, Max_States, Repeated);
                     if Repeated.Start = No_State then
                        Status := Too_Many_States;
                        Offset := Relative_Offset (Pattern'First, Pos - 1);
                        return;
                     end if;
                     Atom := Repeated;
                  end if;

                  if Pos >= Positive'First
                    and then Pos <= Nat (Pattern'Last)
                    and then Pattern (Positive (Pos)) in '*' | '+' | '?' | '{'
                  then
                     Status := Invalid_Quantifier;
                     Offset := Relative_Offset (Pattern'First, Pos);
                     return;
                  end if;
               end if;

               if Have_Frag then
                  Concat (Result.Expression, Current, Atom, Ok);
                  if not Ok then
                     Status := Too_Many_States;
                     Offset := Relative_Offset (Pattern'First, Pos);
                     return;
                  end if;
               else
                  Current := Atom;
                  Have_Frag := True;
               end if;
            end if;
         end loop;

         if Stop_At_Close and then not Closing_Found then
            Status := Unsupported_Syntax;
            Offset := Pattern'Length;
            return;
         end if;

         if not Have_Frag then
            Epsilon_Fragment (Result.Expression, Max_States, Current, Ok);
            if not Ok then
               Status := Too_Many_States;
               Offset := Pattern'Length;
               return;
            end if;
            Have_Frag := True;
         end if;

         if Have_Alternative then
            Append_Alternative (Result.Expression, Alternatives, Current, Max_States, Ok);
            if not Ok then
               Status := Too_Many_States;
               Offset := Pattern'Length;
               return;
            end if;
         else
            Alternatives := Current;
         end if;

         Expr := Alternatives;
         Good := True;
      end Parse_Expression;

      Alternatives : Fragment;
      Closed       : Boolean;
      Status       : Compile_Status;
      Offset       : Natural;
      Ok           : Boolean;
   begin
      Result.Expression := (others => <>);
      Result.Expression.Compiled_Mode := Character_Mode;

      if Pattern'Length = 0 then
         Result.Status := Empty_Pattern;
         return Result;
      end if;

      if Pattern'Length > Max_Pattern_Length then
         Result.Status := Pattern_Too_Long;
         Result.Error_Offset := Max_Pattern_Length + 1;
         return Result;
      end if;

      Parse_Expression
        (False, (others => Option_Inherit), Alternatives, Closed, Status, Offset, Ok);
      if not Ok then
         Result.Status := Status;
         Result.Error_Offset := Offset;
         return Result;
      end if;

      New_State (Result.Expression, Node_Match, Max_States, Match);
      if Match = No_State then
         Result.Status := Too_Many_States;
         Result.Error_Offset := Pattern'Length;
         return Result;
      end if;

      Patch_To (Result.Expression, Alternatives, Match);
      Result.Expression.Start := Alternatives.Start;
      Result.Expression.Valid := True;
      Store_Source (Result.Expression, Pattern, Source_Pattern);
      Result.Status := Compile_Ok;
      Result.Error_Offset := 0;
      return Result;
   end Compile;

   function Is_Valid (Expression : Regexp) return Boolean is
     (Expression.Valid);

   function Capture_Count (Expression : Regexp) return Natural is
     (if Expression.Valid then Expression.Capture_Count else 0);

   function Has_Captures (Expression : Regexp) return Boolean is
     (Capture_Count (Expression) > 0);

   function Uses_Anchors (Expression : Regexp) return Boolean is
   begin
      if not Expression.Valid then
         return False;
      end if;

      for I in 1 .. Expression.State_Count loop
         if Expression.States (I).Kind in Node_Start_Line | Node_End_Line then
            return True;
         end if;
      end loop;

      return False;
   end Uses_Anchors;

   function May_Match_Empty (Expression : Regexp) return Boolean is
      Pending : array (Positive range 1 .. Default_Max_States) of State_Index := [others => No_State];
      Visited : array (Positive range 1 .. Default_Max_States) of Boolean := [others => False];
      Head    : Positive := 1;
      Tail    : Natural := 0;

      procedure Enqueue (Index : State_Index) is
      begin
         if Index = No_State or else Visited (Positive (Index)) then
            return;
         end if;

         Visited (Positive (Index)) := True;
         Tail := Tail + 1;
         Pending (Tail) := Index;
      end Enqueue;
   begin
      if not Expression.Valid or else Expression.Start = No_State then
         return False;
      end if;

      Enqueue (Expression.Start);
      while Head <= Tail loop
         declare
            Node : constant State := Expression.States (Positive (Pending (Head)));
         begin
            Head := Head + 1;
            case Node.Kind is
               when Node_Match =>
                  return True;

               when Node_Split =>
                  Enqueue (Node.Out_1);
                  Enqueue (Node.Out_2);

               when Node_Start_Line
                  | Node_End_Line
                  | Node_Word_Boundary
                  | Node_Not_Word_Boundary
                  | Node_Lookahead_Positive
                  | Node_Lookahead_Negative
                  | Node_Lookbehind_Positive
                  | Node_Lookbehind_Negative
                  | Node_Capture_Start
                  | Node_Capture_End
                  | Node_Backreference
                  | Node_Atomic =>
                  Enqueue (Node.Out_1);

               when others =>
                  null;
            end case;
         end;
      end loop;

      return False;
   end May_Match_Empty;

   function Features (Expression : Regexp) return Pattern_Features is
      Result : Pattern_Features;
   begin
      if not Expression.Valid then
         return Result;
      end if;

      Result.Has_Captures := Expression.Capture_Count > 0;
      Result.Has_Backreferences := Expression.Has_Backreferences;
      Result.Has_Atomic := Expression.Has_Atomic;
      Result.May_Match_Empty := May_Match_Empty (Expression);

      for I in 1 .. Natural'Min (Expression.Capture_Count, Max_Captures) loop
         if Expression.Capture_Name_Lengths (I) /= 0 then
            Result.Has_Named_Captures := True;
            exit;
         end if;
      end loop;

      for I in 1 .. Expression.State_Count loop
         declare
            Node : constant State := Expression.States (I);
         begin
            case Node.Kind is
               when Node_Start_Line | Node_End_Line =>
                  Result.Has_Anchors := True;

               when Node_Word_Boundary | Node_Not_Word_Boundary =>
                  Result.Has_Word_Boundaries := True;

               when Node_Lookahead_Positive
                  | Node_Lookahead_Negative
                  | Node_Lookbehind_Positive
                  | Node_Lookbehind_Negative =>
                  Result.Has_Lookaround := True;

               when Node_Class =>
                  Result.Has_Character_Classes := True;

               when Node_Any =>
                  Result.Has_Dot := True;

               when Node_Split =>
                  Result.Has_Splits := True;

               when others =>
                  null;
            end case;

            if Node.Modes /=
              (Case_Sensitive => Option_Inherit,
               Dot_Matches_Newline => Option_Inherit,
               Multiline_Anchors => Option_Inherit,
               Free_Spacing => Option_Inherit)
            then
               Result.Has_Scoped_Options := True;
            end if;
         end;
      end loop;

      return Result;
   end Features;

   function Is_Literal (Expression : Regexp) return Boolean is
   begin
      if not Expression.Valid then
         return False;
      end if;

      for I in 1 .. Expression.State_Count loop
         if Expression.States (I).Kind not in Node_Char | Node_Match then
            return False;
         end if;
      end loop;

      return Expression.State_Count > 1;
   end Is_Literal;

   function Is_Anchored (Expression : Regexp) return Boolean is
   begin
      return Uses_Anchors (Expression);
   end Is_Anchored;

   function Is_Whole_Line (Expression : Regexp) return Boolean is
      Has_Start : Boolean := False;
      Has_End   : Boolean := False;
   begin
      if not Expression.Valid then
         return False;
      end if;

      for I in 1 .. Expression.State_Count loop
         case Expression.States (I).Kind is
            when Node_Start_Line =>
               Has_Start := True;
            when Node_End_Line =>
               Has_End := True;
            when others =>
               null;
         end case;
      end loop;

      return Has_Start and then Has_End;
   end Is_Whole_Line;

   function Needs_Backtracking (Expression : Regexp) return Boolean is
      F : constant Pattern_Features := Features (Expression);
   begin
      return F.Has_Splits
        or else F.Has_Backreferences
        or else F.Has_Lookaround
        or else F.Has_Atomic;
   end Needs_Backtracking;

   function Can_Stream_Safely (Expression : Regexp) return Boolean is
      F : constant Pattern_Features := Features (Expression);
   begin
      return Expression.Valid and then not F.Has_Lookaround;
   end Can_Stream_Safely;

   function Recommended_Strategy (Expression : Regexp) return Search_Strategy is
      Prefix : String (1 .. Default_Max_Pattern_Length);
      Last   : Natural;
      Status : Copy_Status;
   begin
      if not Expression.Valid then
         return Search_Invalid;
      elsif Is_Literal (Expression) then
         return Search_Literal;
      elsif Is_Anchored (Expression) then
         return Search_Anchored;
      end if;

      Required_Prefix (Expression, Prefix, Last, Status);
      if Status = Copy_Ok and then Last /= 0 then
         return Search_Prefix;
      end if;

      return Search_General;
   end Recommended_Strategy;

   function Summary (Expression : Regexp) return Expression_Summary is
      Prefix : String (1 .. Default_Max_Pattern_Length);
      Last   : Natural;
      Status : Copy_Status;
      Result : Expression_Summary;
   begin
      if not Expression.Valid then
         return Result;
      end if;

      Required_Prefix (Expression, Prefix, Last, Status);
      Result :=
        (Valid                  => True,
         State_Count            => Expression.State_Count,
         Capture_Count          => Expression.Capture_Count,
         Feature                => Features (Expression),
         Source_Kind            => Expression.Source_Kind,
         Source_Length          => Expression.Source_Length,
         Required_Prefix_Length => (if Status = Copy_Ok then Last else 0),
         Strategy               => Recommended_Strategy (Expression));
      return Result;
   end Summary;

   function Fingerprint (Expression : Regexp) return Pattern_Fingerprint is
      Hash : Natural := 2_166_136_261 mod (Natural'Last / 2);

      procedure Mix (Value : Natural) is
      begin
         Hash := (Hash + (Value mod 65_521) + 1) mod (Natural'Last / 2);
      end Mix;
   begin
      if not Expression.Valid then
         return (others => 0);
      end if;

      Mix (Expression.State_Count);
      Mix (Expression.Capture_Count);
      Mix (Pattern_Source_Kind'Pos (Expression.Source_Kind));
      for I in 1 .. Expression.Source_Length loop
         Mix (Character'Pos (Expression.Source_Pattern (I)));
      end loop;

      return
        (Hash          => Hash,
         Source_Length => Expression.Source_Length,
         State_Count   => Expression.State_Count,
         Capture_Count => Expression.Capture_Count);
   end Fingerprint;

   function Metadata (Expression : Regexp) return Pattern_Metadata is
   begin
      if not Expression.Valid then
         return (others => <>);
      end if;

      return
        (Valid              => True,
         Source_Kind        => Expression.Source_Kind,
         Source_Length      => Expression.Source_Length,
         Max_Pattern_Length => Default_Max_Pattern_Length,
         Max_States         => Default_Max_States,
         Feature            => Features (Expression),
         Fingerprint        => Fingerprint (Expression));
   end Metadata;

   function Source_Kind (Expression : Regexp) return Pattern_Source_Kind is
   begin
      return (if Expression.Valid then Expression.Source_Kind else Source_Unknown);
   end Source_Kind;

   procedure Copy_Source_Pattern
     (Expression : Regexp;
      Output     : out String;
      Last       : out Natural;
      Status     : out Copy_Status)
   is
   begin
      Output := [others => Character'Val (0)];
      Last := 0;
      if not Expression.Valid or else Expression.Source_Length = 0 then
         Status := Copy_No_Match;
         return;
      end if;

      if Expression.Source_Length > Output'Length then
         Status := Copy_Output_Too_Small;
         return;
      end if;

      for I in 1 .. Expression.Source_Length loop
         Output (Output'First + I - 1) := Expression.Source_Pattern (I);
      end loop;
      Last := Expression.Source_Length;

      Status := Copy_Ok;
   end Copy_Source_Pattern;

   procedure Validate_Policy
     (Expression : Regexp;
      Policy     : Pattern_Policy;
      Status     : out Pattern_Policy_Status;
      Feature    : out Pattern_Features)
   is
   begin
      Feature := Features (Expression);
      if not Expression.Valid then
         Status := Policy_Invalid_Regexp;
      elsif (Feature.Has_Captures and then not Policy.Allow_Captures)
        or else (Feature.Has_Named_Captures and then not Policy.Allow_Named_Captures)
        or else (Feature.Has_Backreferences and then not Policy.Allow_Backreferences)
        or else (Feature.Has_Anchors and then not Policy.Allow_Anchors)
        or else (Feature.Has_Word_Boundaries and then not Policy.Allow_Word_Boundaries)
        or else (Feature.Has_Lookaround and then not Policy.Allow_Lookaround)
        or else (Feature.Has_Atomic and then not Policy.Allow_Atomic)
        or else (Feature.Has_Character_Classes and then not Policy.Allow_Character_Classes)
        or else (Feature.Has_Dot and then not Policy.Allow_Dot)
      then
         Status := Policy_Disallowed_Feature;
      elsif Feature.May_Match_Empty and then not Policy.Allow_Empty_Match then
         Status := Policy_Disallowed_Empty_Match;
      else
         Status := Policy_Ok;
      end if;
   end Validate_Policy;

   function Validate_Policy_Detail
     (Expression : Regexp;
      Policy     : Pattern_Policy)
      return Pattern_Policy_Diagnostic
   is
      F : constant Pattern_Features := Features (Expression);
   begin
      if not Expression.Valid then
         return (Status => Policy_Invalid_Regexp, Feature => Policy_Feature_None);
      elsif F.Has_Captures and then not Policy.Allow_Captures then
         return (Policy_Disallowed_Feature, Policy_Feature_Captures);
      elsif F.Has_Named_Captures and then not Policy.Allow_Named_Captures then
         return (Policy_Disallowed_Feature, Policy_Feature_Named_Captures);
      elsif F.Has_Backreferences and then not Policy.Allow_Backreferences then
         return (Policy_Disallowed_Feature, Policy_Feature_Backreferences);
      elsif F.Has_Anchors and then not Policy.Allow_Anchors then
         return (Policy_Disallowed_Feature, Policy_Feature_Anchors);
      elsif F.Has_Word_Boundaries and then not Policy.Allow_Word_Boundaries then
         return (Policy_Disallowed_Feature, Policy_Feature_Word_Boundaries);
      elsif F.Has_Lookaround and then not Policy.Allow_Lookaround then
         return (Policy_Disallowed_Feature, Policy_Feature_Lookaround);
      elsif F.Has_Atomic and then not Policy.Allow_Atomic then
         return (Policy_Disallowed_Feature, Policy_Feature_Atomic);
      elsif F.Has_Character_Classes and then not Policy.Allow_Character_Classes then
         return (Policy_Disallowed_Feature, Policy_Feature_Character_Classes);
      elsif F.Has_Dot and then not Policy.Allow_Dot then
         return (Policy_Disallowed_Feature, Policy_Feature_Dot);
      elsif F.May_Match_Empty and then not Policy.Allow_Empty_Match then
         return (Policy_Disallowed_Empty_Match, Policy_Feature_Empty_Match);
      else
         return (Status => Policy_Ok, Feature => Policy_Feature_None);
      end if;
   end Validate_Policy_Detail;

   function Compile_Diagnostic (Result : Compile_Result) return Compile_Diagnostic_Record is
      Kind : Diagnostic_Kind := Diagnostic_None;
   begin
      case Result.Status is
         when Compile_Ok =>
            Kind := Diagnostic_None;
         when Pattern_Too_Long | Too_Many_States | Too_Many_Captures =>
            Kind := Diagnostic_Limit;
         when Unsupported_Syntax =>
            Kind := Diagnostic_Unsupported;
         when others =>
            Kind := Diagnostic_Syntax;
      end case;

      return (Status => Result.Status, Kind => Kind, Offset => Result.Error_Offset);
   end Compile_Diagnostic;

   function Replacement_Diagnostic
     (Expression  : Regexp;
      Replacement : String)
      return Replacement_Diagnostic_Record
   is
      Detail : constant Replacement_Validation_Result := Validate_Replacement_Detail (Expression, Replacement);
      Kind   : Diagnostic_Kind := Diagnostic_None;
   begin
      case Detail.Status is
         when Replacement_Ok =>
            Kind := Diagnostic_None;
         when Replacement_Invalid_Regexp =>
            Kind := Diagnostic_Invalid_Expression;
         when Replacement_Unknown_Capture =>
            Kind := Diagnostic_Unknown_Capture;
         when others =>
            Kind := Diagnostic_Invalid_Replacement;
      end case;

      return (Detail => Detail, Kind => Kind);
   end Replacement_Diagnostic;

   function Capture_Index (Expression : Regexp; Name : String) return Natural is
   begin
      if not Expression.Valid
        or else Name'Length = 0
        or else Name'Length > Max_Capture_Name_Length
      then
         return 0;
      end if;

      for I in 1 .. Natural'Min (Expression.Capture_Count, Max_Captures) loop
         if Capture_Name_Equals (Expression, I, Name) then
            return I;
         end if;
      end loop;

      return 0;
   end Capture_Index;

   procedure Named_Captures
     (Expression : Regexp;
      Indexes    : out Capture_Index_Array;
      Count      : out Natural;
      Complete   : out Boolean)
   is
   begin
      Indexes := [others => 0];
      Count := 0;
      Complete := True;

      if not Expression.Valid then
         return;
      end if;

      for I in 1 .. Natural'Min (Expression.Capture_Count, Max_Captures) loop
         if Expression.Capture_Name_Lengths (I) /= 0 then
            if Count < Indexes'Length then
               Indexes (Indexes'First + Count) := I;
               Count := Count + 1;
            else
               Complete := False;
            end if;
         end if;
      end loop;
   end Named_Captures;

   procedure Capture_Name
     (Expression : Regexp;
      Index      : Positive;
      Output     : out String;
      Last       : out Natural;
      Status     : out Copy_Status)
   is
      Len : Natural;
   begin
      Output := [others => Character'Val (0)];
      Last := 0;

      if not Expression.Valid
        or else Index > Expression.Capture_Count
        or else Index > Max_Captures
      then
         Status := Copy_No_Match;
         return;
      end if;

      Len := Expression.Capture_Name_Lengths (Index);
      if Len = 0 then
         Status := Copy_No_Match;
         return;
      elsif Len > Output'Length then
         Status := Copy_Output_Too_Small;
         return;
      end if;

      for I in 1 .. Len loop
         Output (Positive (Nat (Output'First) + I - 1)) := Expression.Capture_Names (Index) (I);
      end loop;
      Last := Len;
      Status := Copy_Ok;
   end Capture_Name;

   function Line_Column (Text : String; Offset : Natural) return Source_Position is
      Target : Natural;
      Pos    : Natural;
      Line   : Natural := 1;
      Column : Natural := 1;
   begin
      if Offset = 0 or else Offset > Text'Length + 1 then
         return (Line => 0, Column => 0);
      end if;

      Target := Nat (Text'First) + Offset - 1;
      Pos := Nat (Text'First);
      while Pos < Target and then Pos <= Nat (Text'Last) loop
         if Text (Positive (Pos)) = Character'Val (13) then
            Line := Line + 1;
            Column := 1;
            if Pos < Nat (Text'Last) and then Text (Positive (Pos + 1)) = Character'Val (10) then
               Pos := Pos + 1;
            end if;
         elsif Text (Positive (Pos)) = Character'Val (10) then
            Line := Line + 1;
            Column := 1;
         else
            Column := Column + 1;
         end if;
         Pos := Pos + 1;
      end loop;

      return (Line => Line, Column => Column);
   end Line_Column;

   function Match_Line_Range (Text : String; Found : Match_Result) return Text_Range is
      Target : Natural;
      Start  : Natural;
      Finish : Natural;
   begin
      if Found.Status /= Match_Ok
        or else Found.First = 0
        or else Found.First > Text'Length + 1
        or else (Found.Last >= Found.First and then Found.Last > Text'Length)
      then
         return (First => 0, Last => 0);
      end if;

      if Text'Length = 0 then
         return (First => 1, Last => 0);
      end if;

      Target := Natural'Min (Found.First, Text'Length);
      Start := Target;
      while Start > 1 loop
         exit when Text (Positive (Nat (Text'First) + Start - 2)) in Character'Val (10) | Character'Val (13);
         Start := Start - 1;
      end loop;

      Finish := Target;
      while Finish <= Text'Length loop
         exit when Text (Positive (Nat (Text'First) + Finish - 1)) in Character'Val (10) | Character'Val (13);
         Finish := Finish + 1;
      end loop;

      return (First => Start, Last => Finish - 1);
   end Match_Line_Range;

   function Match_Length (Found : Match_Result) return Natural is
   begin
      if Found.Status /= Match_Ok or else Found.Last < Found.First then
         return 0;
      else
         return Found.Last - Found.First + 1;
      end if;
   end Match_Length;

   function Contains_Offset (Found : Match_Result; Offset : Natural) return Boolean is
   begin
      return Found.Status = Match_Ok
        and then Found.Last >= Found.First
        and then Offset >= Found.First
        and then Offset <= Found.Last;
   end Contains_Offset;

   function Before_Match (Text : String; Found : Match_Result) return Text_Range is
      Before : Text_Range;
      Match  : Text_Range;
      After  : Text_Range;
      Status : Copy_Status;
   begin
      Match_Context (Text, Found, Before, Match, After, Status);
      return (if Status = Copy_Ok then Before else (First => 0, Last => 0));
   end Before_Match;

   function After_Match (Text : String; Found : Match_Result) return Text_Range is
      Before : Text_Range;
      Match  : Text_Range;
      After  : Text_Range;
      Status : Copy_Status;
   begin
      Match_Context (Text, Found, Before, Match, After, Status);
      return (if Status = Copy_Ok then After else (First => 0, Last => 0));
   end After_Match;

   procedure Match_Context
     (Text   : String;
      Found  : Match_Result;
      Before : out Text_Range;
      Match  : out Text_Range;
      After  : out Text_Range;
      Status : out Copy_Status)
   is
      After_First : Natural;
   begin
      Before := (First => 0, Last => 0);
      Match := (First => 0, Last => 0);
      After := (First => 0, Last => 0);

      if Found.Status /= Match_Ok
        or else Found.First = 0
        or else Found.First > Text'Length + 1
        or else (Found.Last >= Found.First and then Found.Last > Text'Length)
      then
         Status := Copy_No_Match;
         return;
      end if;

      Before := (First => 1, Last => Found.First - 1);
      Match := (First => Found.First, Last => Found.Last);
      After_First := (if Found.Last < Found.First then Found.First else Found.Last + 1);
      After := (First => After_First, Last => Text'Length);
      Status := Copy_Ok;
   end Match_Context;

   procedure Find_First_Line
     (Expression : Regexp;
      Text       : String;
      Found      : out Match_Result;
      Position   : out Source_Position;
      Line       : out Text_Range;
      Options    : Match_Options := (others => <>))
   is
   begin
      Found := Find_First (Expression, Text, Options);
      if Found.Status = Match_Ok then
         Position := Line_Column (Text, Found.First);
         Line := Match_Line_Range (Text, Found);
      else
         Position := (Line => 0, Column => 0);
         Line := (First => 0, Last => 0);
      end if;
   end Find_First_Line;

   function Compile_Literal
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
   is
   begin
      if Pattern'Length = 0 then
         return Compile (Pattern, Max_Pattern_Length, Max_States);
      elsif Pattern'Length > Max_Pattern_Length then
         return
           (Status       => Pattern_Too_Long,
            Expression   => <>,
            Error_Offset => Max_Pattern_Length + 1);
      end if;

      declare
         Escaped : constant String := Escape_Literal (Pattern);
         Result  : Compile_Result := Compile (Escaped, Escaped'Length, Max_States);
      begin
         if Result.Status = Compile_Ok then
            Store_Source (Result.Expression, Pattern, Source_Literal);
         end if;
         return Result;
      end;
   end Compile_Literal;

   function Compile_Literal_Set
     (Text               : String;
      Literals           : Text_Range_Array;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
   is
      Pattern       : String (1 .. Max_Pattern_Length) := (others => Character'Val (0));
      Last          : Natural := 0;
      Status        : Copy_Status;
   begin
      if Literals'Length = 0 then
         return Compile ("", Max_Pattern_Length, Max_States);
      end if;

      Build_Literal_Alternation (Text, Literals, Pattern, Last, Status);
      if Status = Copy_No_Match then
         return (Status => Unsupported_Syntax, Expression => <>, Error_Offset => 0);
      elsif Status = Copy_Output_Too_Small then
         return (Status => Pattern_Too_Long, Expression => <>, Error_Offset => Max_Pattern_Length + 1);
      end if;

      if Last = 0 then
         if Max_Pattern_Length < 4 then
            return (Status => Pattern_Too_Long, Expression => <>, Error_Offset => Max_Pattern_Length + 1);
         end if;
         declare
            Result : Compile_Result := Compile ("(?:)", Max_Pattern_Length, Max_States);
         begin
            if Result.Status = Compile_Ok then
               Store_Source (Result.Expression, "(?:)", Source_Literal_Set);
            end if;
            return Result;
         end;
      end if;

      declare
         Result : Compile_Result := Compile (Pattern (1 .. Last), Max_Pattern_Length, Max_States);
      begin
         if Result.Status = Compile_Ok then
            Store_Source (Result.Expression, Pattern (1 .. Last), Source_Literal_Set);
         end if;
         return Result;
      end;
   end Compile_Literal_Set;

   function Compile_Literal_Word_Set
     (Text               : String;
      Literals           : Text_Range_Array;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
   is
      Pattern       : String (1 .. Max_Pattern_Length) := (others => Character'Val (0));
      Last          : Natural := 0;
      Status        : Copy_Status;
   begin
      if Literals'Length = 0 then
         return Compile ("", Max_Pattern_Length, Max_States);
      end if;

      Build_Literal_Word_Alternation (Text, Literals, Pattern, Last, Status);
      if Status = Copy_No_Match then
         return (Status => Unsupported_Syntax, Expression => <>, Error_Offset => 0);
      elsif Status = Copy_Output_Too_Small then
         return (Status => Pattern_Too_Long, Expression => <>, Error_Offset => Max_Pattern_Length + 1);
      end if;

      declare
         Result : Compile_Result := Compile (Pattern (1 .. Last), Max_Pattern_Length, Max_States);
      begin
         if Result.Status = Compile_Ok then
            Store_Source (Result.Expression, Pattern (1 .. Last), Source_Literal_Word_Set);
         end if;
         return Result;
      end;
   end Compile_Literal_Word_Set;

   function Compile_Wrapped
     (Prefix             : String;
      Pattern            : String;
      Suffix             : String;
      Literal            : Boolean;
      Kind               : Pattern_Source_Kind;
      Max_Pattern_Length : Positive;
      Max_States         : Positive)
      return Compile_Result
   is
   begin
      declare
         Inner : constant String := (if Literal then Escape_Literal (Pattern) else Pattern);
      begin
         if Prefix'Length + Inner'Length + Suffix'Length > Max_Pattern_Length then
            return (Status => Pattern_Too_Long, Expression => <>, Error_Offset => Max_Pattern_Length + 1);
         end if;

         declare
            Generated : constant String := Prefix & Inner & Suffix;
            Result    : Compile_Result := Compile (Generated, Max_Pattern_Length, Max_States);
         begin
            if Result.Status = Compile_Ok then
               Store_Source (Result.Expression, Generated, Kind);
            end if;
            return Result;
         end;
      end;
   end Compile_Wrapped;

   function Compile_Anchored
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
   is
   begin
      return Compile_Wrapped ("^(?:", Pattern, ")$", False, Source_Anchored, Max_Pattern_Length, Max_States);
   end Compile_Anchored;

   function Compile_Whole_Word
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
   is
   begin
      return Compile_Wrapped ("\b(?:", Pattern, ")\b", False, Source_Whole_Word, Max_Pattern_Length, Max_States);
   end Compile_Whole_Word;

   function Compile_Literal_Anchored
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
   is
   begin
      return Compile_Wrapped ("^(?:", Pattern, ")$", True, Source_Literal_Anchored, Max_Pattern_Length, Max_States);
   end Compile_Literal_Anchored;

   function Compile_Literal_Whole_Word
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
   is
   begin
      return Compile_Wrapped ("\b(?:", Pattern, ")\b", True, Source_Literal_Whole_Word, Max_Pattern_Length, Max_States);
   end Compile_Literal_Whole_Word;

   function Compile_Line
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
   is
   begin
      return Compile_Wrapped ("(?m:^(?:", Pattern, ")$)", False, Source_Line, Max_Pattern_Length, Max_States);
   end Compile_Line;

   function Compile_Literal_Line
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
   is
   begin
      return Compile_Wrapped ("(?m:^(?:", Pattern, ")$)", True, Source_Literal_Line, Max_Pattern_Length, Max_States);
   end Compile_Literal_Line;

   function Supports_Syntax (Feature : Syntax_Feature) return Boolean is
   begin
      case Feature is
         when Syntax_Literals =>
            return True;
         when Syntax_Dot =>
            return True;
         when Syntax_Anchors =>
            return True;
         when Syntax_Character_Classes =>
            return True;
         when Syntax_Unicode_Properties =>
            return True;
         when Syntax_Posix_Classes =>
            return True;
         when Syntax_Class_Set_Operations =>
            return True;
         when Syntax_Groups =>
            return True;
         when Syntax_Named_Captures =>
            return True;
         when Syntax_Non_Capturing_Groups =>
            return True;
         when Syntax_Alternation =>
            return True;
         when Syntax_Lookahead =>
            return True;
         when Syntax_Lookbehind =>
            return True;
         when Syntax_Backreferences =>
            return True;
         when Syntax_Bounded_Repeats =>
            return True;
         when Syntax_Lazy_Quantifiers =>
            return True;
         when Syntax_Possessive_Quantifiers =>
            return True;
         when Syntax_Atomic_Groups =>
            return True;
         when Syntax_Inline_Options =>
            return True;
         when Syntax_Word_Boundaries =>
            return True;
      end case;
   end Supports_Syntax;

   function Syntax_Feature_Image (Feature : Syntax_Feature) return String is
   begin
      case Feature is
         when Syntax_Literals => return "literals";
         when Syntax_Dot => return "dot";
         when Syntax_Anchors => return "anchors";
         when Syntax_Character_Classes => return "character classes";
         when Syntax_Unicode_Properties => return "unicode properties";
         when Syntax_Posix_Classes => return "posix classes";
         when Syntax_Class_Set_Operations => return "class set operations";
         when Syntax_Groups => return "groups";
         when Syntax_Named_Captures => return "named captures";
         when Syntax_Non_Capturing_Groups => return "non-capturing groups";
         when Syntax_Alternation => return "alternation";
         when Syntax_Lookahead => return "lookahead";
         when Syntax_Lookbehind => return "lookbehind";
         when Syntax_Backreferences => return "backreferences";
         when Syntax_Bounded_Repeats => return "bounded repeats";
         when Syntax_Lazy_Quantifiers => return "lazy quantifiers";
         when Syntax_Possessive_Quantifiers => return "possessive quantifiers";
         when Syntax_Atomic_Groups => return "atomic groups";
         when Syntax_Inline_Options => return "inline options";
         when Syntax_Word_Boundaries => return "word boundaries";
      end case;
   end Syntax_Feature_Image;

   procedure Supported_Syntax
     (Features : out Syntax_Feature_Array;
      Count    : out Natural;
      Complete : out Boolean)
   is
   begin
      Features := [others => Syntax_Literals];
      Count := 0;
      Complete := True;

      for Feature in Syntax_Feature loop
         if Count < Features'Length then
            Features (Features'First + Count) := Feature;
            Count := Count + 1;
         else
            Complete := False;
         end if;
      end loop;
   end Supported_Syntax;

   procedure Supported_Syntax_Detail
     (Support       : out Syntax_Support_Array;
      Count         : out Natural;
      Complete      : out Boolean;
      Notes         : out String;
      Notes_Last    : out Natural;
      Examples      : out String;
      Examples_Last : out Natural)
   is
      Ok : Boolean := True;

      procedure Append
        (Buffer : in out String;
         Last   : in out Natural;
         Text   : String;
         First  : out Natural;
         Final  : out Natural)
      is
      begin
         if Text'Length = 0 then
            First := 0;
            Final := 0;
            return;
         end if;

         First := Last + 1;
         if Text'Length > Buffer'Length - Last then
            Ok := False;
            Final := Last;
         else
            for I in Text'Range loop
               Last := Last + 1;
               Buffer (Buffer'First + Last - 1) := Text (I);
            end loop;
            Final := Last;
         end if;
      end Append;
   begin
      Support := [others => (others => <>)];
      Notes := [others => Character'Val (0)];
      Examples := [others => Character'Val (0)];
      Count := 0;
      Notes_Last := 0;
      Examples_Last := 0;
      Complete := True;

      for Feature in Syntax_Feature loop
         if Count = Support'Length then
            Complete := False;
         else
            Count := Count + 1;
            Support (Support'First + Count - 1).Feature := Feature;
            Support (Support'First + Count - 1).Supported := Supports_Syntax (Feature);
            Append
              (Notes,
               Notes_Last,
               Syntax_Feature_Image (Feature),
               Support (Support'First + Count - 1).Note_First,
               Support (Support'First + Count - 1).Note_Last);
            Append
              (Examples,
               Examples_Last,
               Syntax_Feature_Image (Feature),
               Support (Support'First + Count - 1).Example_First,
               Support (Support'First + Count - 1).Example_Last);
         end if;
      end loop;

      Complete := Complete and Ok;
   end Supported_Syntax_Detail;

   function Validate_UTF_8 (Text : String) return UTF_8_Validation_Result is
      Pos : Natural := 1;

      function Byte (Offset : Natural) return Natural is
        (Character'Pos (Text (Text'First + Offset - 1)));

      function Continuation (Offset : Natural) return Boolean is
        (Offset <= Text'Length and then Byte (Offset) in 16#80# .. 16#BF#);
   begin
      while Pos <= Text'Length loop
         declare
            B : constant Natural := Byte (Pos);
         begin
            if B <= 16#7F# then
               Pos := Pos + 1;
            elsif B in 16#C2# .. 16#DF# and then Continuation (Pos + 1) then
               Pos := Pos + 2;
            elsif B in 16#E0# .. 16#EF#
              and then Continuation (Pos + 1)
              and then Continuation (Pos + 2)
            then
               Pos := Pos + 3;
            elsif B in 16#F0# .. 16#F4#
              and then Continuation (Pos + 1)
              and then Continuation (Pos + 2)
              and then Continuation (Pos + 3)
            then
               Pos := Pos + 4;
            else
               return (Valid => False, Error_Offset => Pos);
            end if;
         end;
      end loop;

      return (Valid => True, Error_Offset => 0);
   end Validate_UTF_8;

   procedure Build_Character_Class
     (Members : String;
      Negated : Boolean;
      Pattern : out String;
      Last    : out Natural;
      Status  : out Copy_Status)
   is
      Ok : Boolean := True;

      procedure Append (Text : String) is
      begin
         if Text'Length > Pattern'Length - Last then
            Ok := False;
         elsif Ok then
            for I in Text'Range loop
               Last := Last + 1;
               Pattern (Pattern'First + Last - 1) := Text (I);
            end loop;
         end if;
      end Append;
   begin
      Pattern := [others => Character'Val (0)];
      Last := 0;
      Append ("[");
      if Negated then
         Append ("^");
      end if;
      Append (Members);
      Append ("]");
      Status := (if Ok then Copy_Ok else Copy_Output_Too_Small);
   end Build_Character_Class;

   function Escape_Literal (Pattern : String) return String
      with SPARK_Mode => Off
   is
   begin
      if Pattern'Length = 0 then
         return "";
      end if;

      declare
         Escaped : String (1 .. Pattern'Length * 2) := (others => Character'Val (0));
         Last    : Natural := 0;

         procedure Append (Ch : Character) is
         begin
            Last := Last + 1;
            Escaped (Last) := Ch;
         end Append;
      begin
         for Ch of Pattern loop
            if Ch in '.' | '*' | '+' | '?' | '(' | ')' | '[' | ']' | '{' | '}'
                    | '\' | '^' | '$' | '|'
            then
               Append ('\');
            end if;
            Append (Ch);
         end loop;

         return Escaped (1 .. Last);
      end;
   end Escape_Literal;

   function Has_Match
     (Expression : Regexp;
      Text       : String;
      Options    : Match_Options := (others => <>))
      return Boolean
   is
   begin
      return Find_First (Expression, Text, Options).Status = Match_Ok;
   end Has_Match;

   procedure Consume_Step
     (Options : Match_Options;
      Steps   : in out Natural;
      Step_Limited : in out Boolean)
   is
   begin
      if Step_Limited then
         return;
      end if;

      if Options.Abort_Callback /= null and then Options.Abort_Callback.all then
         Step_Limited := True;
         return;
      end if;

      if Steps >= Options.Max_Steps then
         Step_Limited := True;
      else
         Steps := Steps + 1;
      end if;
   end Consume_Step;

   procedure Check_Lookbehind
     (Expression   : Regexp;
      Start        : State_Index;
      Width        : Natural;
      Text         : String;
      Position     : Natural;
      Options      : Match_Options;
      Steps        : in out Natural;
      Step_Limited : in out Boolean;
      Passed       : out Boolean);

   procedure Check_Lookahead
     (Expression   : Regexp;
      Start        : State_Index;
      Text         : String;
      Start_Pos    : Natural;
      Options      : Match_Options;
      Steps        : in out Natural;
      Step_Limited : in out Boolean;
      Passed       : out Boolean)
   is
      Current : Active_Set := [others => False];
      Next    : Active_Set;
      Pos     : Natural := Start_Pos;

      function Any_Active (Set : Active_Set) return Boolean is
      begin
         for I in 1 .. Expression.State_Count loop
            if Set (I) then
               return True;
            end if;
         end loop;

         return False;
      end Any_Active;

      procedure Add_Assertion_State (Set : in out Active_Set; Index : State_Index; Position : Natural) is
         Pending : array (Positive range 1 .. Default_Max_States) of State_Index := [others => No_State];
         Head    : Positive := 1;
         Tail    : Natural := 0;
         Passed  : Boolean;

         procedure Enqueue (Candidate : State_Index) is
         begin
            if Step_Limited or else Candidate = No_State then
               return;
            end if;

            if Set (Positive (Candidate)) then
               return;
            end if;

            Consume_Step (Options, Steps, Step_Limited);
            if Step_Limited then
               return;
            end if;

            Set (Positive (Candidate)) := True;
            if Tail < Default_Max_States then
               Tail := Tail + 1;
               Pending (Tail) := Candidate;
            else
               Step_Limited := True;
            end if;
         end Enqueue;
      begin
         Enqueue (Index);

         while Head <= Tail loop
            pragma Loop_Invariant (Head in 1 .. Default_Max_States);
            pragma Loop_Invariant (Tail <= Default_Max_States);
            pragma Loop_Variant (Increases => Head);

            declare
               Current_State : constant State_Index := Pending (Head);
            begin
               if Current_State /= No_State then
                  declare
                     Node : State renames Expression.States (Positive (Current_State));
                  begin
                     case Node.Kind is
                        when Node_Split =>
                           Enqueue (Node.Out_1);
                           Enqueue (Node.Out_2);

                        when Node_Start_Line =>
                           if Position = Nat (Text'First)
                             or else
                                (Effective_Multiline_Anchors (Node, Options)
                                and then Position > Nat (Text'First)
                                and then Position <= Nat (Text'Last) + 1
                                and then
                                  (Text (Positive (Position - 1)) = Character'Val (10)
                                   or else Text (Positive (Position - 1)) = Character'Val (13)))
                           then
                              Enqueue (Node.Out_1);
                           end if;

                        when Node_End_Line =>
                           if Position > Nat (Text'Last)
                             or else
                                (Effective_Multiline_Anchors (Node, Options)
                                and then Position <= Nat (Text'Last)
                                and then
                                  (Text (Positive (Position)) = Character'Val (10)
                                   or else Text (Positive (Position)) = Character'Val (13)))
                           then
                              Enqueue (Node.Out_1);
                           end if;

                        when Node_Word_Boundary =>
                           if Word_Boundary_Passes (Text, Position, Options) then
                              Enqueue (Node.Out_1);
                           end if;

                        when Node_Not_Word_Boundary =>
                           if not Word_Boundary_Passes (Text, Position, Options) then
                              Enqueue (Node.Out_1);
                           end if;

                        when Node_Lookahead_Positive =>
                           Check_Lookahead
                             (Expression, Node.Out_2, Text, Position, Options, Steps, Step_Limited, Passed);
                           if Passed then
                              Enqueue (Node.Out_1);
                           end if;

                        when Node_Lookahead_Negative =>
                           Check_Lookahead
                             (Expression, Node.Out_2, Text, Position, Options, Steps, Step_Limited, Passed);
                           if not Passed and then not Step_Limited then
                              Enqueue (Node.Out_1);
                           end if;

                        when Node_Lookbehind_Positive =>
                           Check_Lookbehind
                             (Expression, Node.Out_2, Node.Capture, Text, Position, Options, Steps,
                              Step_Limited, Passed);
                           if Passed then
                              Enqueue (Node.Out_1);
                           end if;

                        when Node_Lookbehind_Negative =>
                           Check_Lookbehind
                             (Expression, Node.Out_2, Node.Capture, Text, Position, Options, Steps,
                              Step_Limited, Passed);
                           if not Passed and then not Step_Limited then
                              Enqueue (Node.Out_1);
                           end if;

                        when Node_Capture_Start | Node_Capture_End =>
                           Enqueue (Node.Out_1);

                        when others =>
                           null;
                     end case;
                  end;
               end if;
            end;

            if Head = Default_Max_States then
               exit;
            end if;
            Head := Head + 1;
         end loop;
      end Add_Assertion_State;
   begin
      Passed := False;

      if Start = No_State
        or else Start_Pos < Nat (Text'First)
        or else Start_Pos > Nat (Text'Last) + 1
      then
         return;
      end if;

      Add_Assertion_State (Current, Start, Pos);
      loop
         pragma Loop_Invariant (Pos >= Nat (Text'First));
         pragma Loop_Invariant (Pos >= Positive'First);
         pragma Loop_Invariant (Pos <= Nat (Text'Last) + 1);
         pragma Loop_Variant (Increases => Pos);

         for I in 1 .. Expression.State_Count loop
            if Current (I) and then Expression.States (I).Kind = Node_Lookahead_Match then
               Passed := True;
               return;
            end if;
         end loop;

         exit when Pos > Nat (Text'Last);

         Next := [others => False];
         for I in 1 .. Expression.State_Count loop
            if Current (I) then
               declare
                  Node : constant State := Expression.States (I);
               begin
                  Consume_Step (Options, Steps, Step_Limited);
                  if Step_Limited then
                     return;
                  end if;

                  case Node.Kind is
                     when Node_Char =>
                        if Equal_Chars
                            (Node.Ch, Text (Positive (Pos)), Effective_Case_Sensitive (Node, Options))
                        then
                           Add_Assertion_State
                             (Next, Node.Out_1, Pos + Step_Width (Expression, Text, Positive (Pos)));
                        end if;

                     when Node_Any =>
                        if Effective_Dot_Matches_Newline (Node, Options)
                          or else
                            (Text (Positive (Pos)) /= Character'Val (10)
                             and then Text (Positive (Pos)) /= Character'Val (13))
                        then
                           Add_Assertion_State
                             (Next, Node.Out_1, Pos + Step_Width (Expression, Text, Positive (Pos)));
                        end if;

                     when Node_Class =>
                        if Class_Matches
                            (Expression, Node, Text, Positive (Pos), Effective_Case_Sensitive (Node, Options))
                        then
                           Add_Assertion_State
                             (Next, Node.Out_1, Pos + Step_Width (Expression, Text, Positive (Pos)));
                        end if;

                     when others =>
                        null;
                  end case;
               end;
            end if;
         end loop;

         if not Any_Active (Next) then
            exit;
         end if;

         Current := Next;
         Pos := Pos + Step_Width (Expression, Text, Positive (Pos));
      end loop;
   end Check_Lookahead;

   procedure Check_Lookbehind
     (Expression   : Regexp;
      Start        : State_Index;
      Width        : Natural;
      Text         : String;
      Position     : Natural;
      Options      : Match_Options;
      Steps        : in out Natural;
      Step_Limited : in out Boolean;
      Passed       : out Boolean)
   is
   begin
      Passed := False;
      if Position < Nat (Text'First) or else Width > Position - Nat (Text'First) then
         return;
      end if;

      Check_Lookahead
        (Expression, Start, Text, Position - Width, Options, Steps, Step_Limited, Passed);
   end Check_Lookbehind;

   procedure Check_Atomic
     (Expression   : Regexp;
      Start        : State_Index;
      Text         : String;
      Start_Pos    : Natural;
      Options      : Match_Options;
      Steps        : in out Natural;
      Step_Limited : in out Boolean;
      Matched      : out Boolean;
      End_Pos      : out Natural)
   is
      Current : Active_Set := [others => False];
      Next    : Active_Set;
      Pos     : Natural := Start_Pos;

      function Any_Active (Set : Active_Set) return Boolean is
      begin
         for I in 1 .. Expression.State_Count loop
            if Set (I) then
               return True;
            end if;
         end loop;

         return False;
      end Any_Active;

      procedure Add_Atomic_State (Set : in out Active_Set; Index : State_Index; Position : Natural) is
         Pending : array (Positive range 1 .. Default_Max_States) of State_Index := [others => No_State];
         Head    : Positive := 1;
         Tail    : Natural := 0;
         Passed  : Boolean;

         procedure Enqueue (Candidate : State_Index) is
         begin
            if Step_Limited or else Candidate = No_State then
               return;
            end if;

            if Set (Positive (Candidate)) then
               return;
            end if;

            Consume_Step (Options, Steps, Step_Limited);
            if Step_Limited then
               return;
            end if;

            Set (Positive (Candidate)) := True;
            if Tail < Default_Max_States then
               Tail := Tail + 1;
               Pending (Tail) := Candidate;
            else
               Step_Limited := True;
            end if;
         end Enqueue;
      begin
         Enqueue (Index);

         while Head <= Tail loop
            pragma Loop_Invariant (Head in 1 .. Default_Max_States);
            pragma Loop_Invariant (Tail <= Default_Max_States);
            pragma Loop_Variant (Increases => Head);

            declare
               Current_State : constant State_Index := Pending (Head);
            begin
               if Current_State /= No_State then
                  declare
                     Node : State renames Expression.States (Positive (Current_State));
                  begin
                     case Node.Kind is
                        when Node_Split =>
                           Enqueue (Node.Out_1);
                           Enqueue (Node.Out_2);

                        when Node_Start_Line =>
                           if Position = Nat (Text'First)
                             or else
                               (Effective_Multiline_Anchors (Node, Options)
                                and then Position > Nat (Text'First)
                                and then Position <= Nat (Text'Last) + 1
                                and then
                                  (Text (Positive (Position - 1)) = Character'Val (10)
                                   or else Text (Positive (Position - 1)) = Character'Val (13)))
                           then
                              Enqueue (Node.Out_1);
                           end if;

                        when Node_End_Line =>
                           if Position > Nat (Text'Last)
                             or else
                               (Effective_Multiline_Anchors (Node, Options)
                                and then Position <= Nat (Text'Last)
                                and then
                                  (Text (Positive (Position)) = Character'Val (10)
                                   or else Text (Positive (Position)) = Character'Val (13)))
                           then
                              Enqueue (Node.Out_1);
                           end if;

                        when Node_Word_Boundary =>
                           if Word_Boundary_Passes (Text, Position, Options) then
                              Enqueue (Node.Out_1);
                           end if;

                        when Node_Not_Word_Boundary =>
                           if not Word_Boundary_Passes (Text, Position, Options) then
                              Enqueue (Node.Out_1);
                           end if;

                        when Node_Lookahead_Positive =>
                           Check_Lookahead
                             (Expression, Node.Out_2, Text, Position, Options, Steps, Step_Limited, Passed);
                           if Passed then
                              Enqueue (Node.Out_1);
                           end if;

                        when Node_Lookahead_Negative =>
                           Check_Lookahead
                             (Expression, Node.Out_2, Text, Position, Options, Steps, Step_Limited, Passed);
                           if not Passed and then not Step_Limited then
                              Enqueue (Node.Out_1);
                           end if;

                        when Node_Lookbehind_Positive =>
                           Check_Lookbehind
                             (Expression, Node.Out_2, Node.Capture, Text, Position, Options, Steps,
                              Step_Limited, Passed);
                           if Passed then
                              Enqueue (Node.Out_1);
                           end if;

                        when Node_Lookbehind_Negative =>
                           Check_Lookbehind
                             (Expression, Node.Out_2, Node.Capture, Text, Position, Options, Steps,
                              Step_Limited, Passed);
                           if not Passed and then not Step_Limited then
                              Enqueue (Node.Out_1);
                           end if;

                        when others =>
                           null;
                     end case;
                  end;
               end if;
            end;

            if Head = Default_Max_States then
               exit;
            end if;
            Head := Head + 1;
         end loop;
      end Add_Atomic_State;
   begin
      Matched := False;
      End_Pos := Start_Pos;

      if Start = No_State
        or else Start_Pos < Nat (Text'First)
        or else Start_Pos > Nat (Text'Last) + 1
      then
         return;
      end if;

      Add_Atomic_State (Current, Start, Pos);
      loop
         pragma Loop_Invariant (Pos >= Nat (Text'First));
         pragma Loop_Invariant (Pos >= Positive'First);
         pragma Loop_Invariant (Pos <= Nat (Text'Last) + 1);
         pragma Loop_Variant (Increases => Pos);

         for I in 1 .. Expression.State_Count loop
            if Current (I) and then Expression.States (I).Kind = Node_Lookahead_Match then
               Matched := True;
               End_Pos := Pos;
            end if;
         end loop;

         exit when Pos > Nat (Text'Last);

         Next := [others => False];
         for I in 1 .. Expression.State_Count loop
            if Current (I) then
               declare
                  Node : constant State := Expression.States (I);
               begin
                  Consume_Step (Options, Steps, Step_Limited);
                  if Step_Limited then
                     return;
                  end if;

                  case Node.Kind is
                     when Node_Char =>
                        if Equal_Chars
                            (Node.Ch, Text (Positive (Pos)), Effective_Case_Sensitive (Node, Options))
                        then
                           Add_Atomic_State
                             (Next, Node.Out_1, Pos + Step_Width (Expression, Text, Positive (Pos)));
                        end if;

                     when Node_Any =>
                        if Effective_Dot_Matches_Newline (Node, Options)
                          or else
                            (Text (Positive (Pos)) /= Character'Val (10)
                             and then Text (Positive (Pos)) /= Character'Val (13))
                        then
                           Add_Atomic_State
                             (Next, Node.Out_1, Pos + Step_Width (Expression, Text, Positive (Pos)));
                        end if;

                     when Node_Class =>
                        if Class_Matches
                            (Expression, Node, Text, Positive (Pos), Effective_Case_Sensitive (Node, Options))
                        then
                           Add_Atomic_State
                             (Next, Node.Out_1, Pos + Step_Width (Expression, Text, Positive (Pos)));
                        end if;

                     when others =>
                        null;
                  end case;
               end;
            end if;
         end loop;

         if not Any_Active (Next) then
            exit;
         end if;

         Current := Next;
         Pos := Pos + Step_Width (Expression, Text, Positive (Pos));
      end loop;
   end Check_Atomic;

   procedure Add_State
     (Expression   : Regexp;
      Set          : in out Active_Set;
      Index        : State_Index;
      Position     : Natural;
      Text         : String;
      Options      : Match_Options;
      Steps        : in out Natural;
      Step_Limited : in out Boolean)
   is
      Pending : array (Positive range 1 .. Default_Max_States) of State_Index := [others => No_State];
      Head    : Positive := 1;
      Tail    : Natural := 0;

      procedure Enqueue (Candidate : State_Index) is
      begin
         if Step_Limited or else Candidate = No_State then
            return;
         end if;

         if Set (Positive (Candidate)) then
            return;
         end if;

         Consume_Step (Options, Steps, Step_Limited);
         if Step_Limited then
            return;
         end if;

         Set (Positive (Candidate)) := True;
         if Tail < Default_Max_States then
            Tail := Tail + 1;
            Pending (Tail) := Candidate;
         else
            Step_Limited := True;
         end if;
      end Enqueue;
   begin
      Enqueue (Index);

      while Head <= Tail loop
         pragma Loop_Invariant (Head in 1 .. Default_Max_States);
         pragma Loop_Invariant (Tail <= Default_Max_States);
         pragma Loop_Variant (Increases => Head);

         declare
            Current : constant State_Index := Pending (Head);
         begin
            if Current /= No_State then
               declare
                  Node : State renames Expression.States (Positive (Current));
               begin
                  case Node.Kind is
                     when Node_Split =>
                        Enqueue (Node.Out_1);
                        Enqueue (Node.Out_2);

                     when Node_Start_Line =>
                        if Position = Nat (Text'First)
                          or else
                            (Effective_Multiline_Anchors (Node, Options)
                             and then Position > Nat (Text'First)
                             and then Position <= Nat (Text'Last) + 1
                             and then
                               (Text (Positive (Position - 1)) = Character'Val (10)
                                or else Text (Positive (Position - 1)) = Character'Val (13)))
                        then
                           Enqueue (Node.Out_1);
                        end if;

                     when Node_End_Line =>
                        if Position > Nat (Text'Last)
                          or else
                            (Effective_Multiline_Anchors (Node, Options)
                             and then Position <= Nat (Text'Last)
                             and then
                               (Text (Positive (Position)) = Character'Val (10)
                                or else Text (Positive (Position)) = Character'Val (13)))
                        then
                           Enqueue (Node.Out_1);
                        end if;

                     when Node_Word_Boundary =>
                        if Word_Boundary_Passes (Text, Position, Options) then
                           Enqueue (Node.Out_1);
                        end if;

                     when Node_Not_Word_Boundary =>
                        if not Word_Boundary_Passes (Text, Position, Options) then
                           Enqueue (Node.Out_1);
                        end if;

                     when Node_Lookahead_Positive =>
                        declare
                           Passed : Boolean;
                        begin
                           Check_Lookahead
                             (Expression, Node.Out_2, Text, Position, Options, Steps, Step_Limited, Passed);
                           if Passed then
                              Enqueue (Node.Out_1);
                           end if;
                        end;

                     when Node_Lookahead_Negative =>
                        declare
                           Passed : Boolean;
                        begin
                           Check_Lookahead
                             (Expression, Node.Out_2, Text, Position, Options, Steps, Step_Limited, Passed);
                           if not Passed and then not Step_Limited then
                              Enqueue (Node.Out_1);
                           end if;
                        end;

                     when Node_Lookbehind_Positive =>
                        declare
                           Passed : Boolean;
                        begin
                           Check_Lookbehind
                             (Expression, Node.Out_2, Node.Capture, Text, Position, Options, Steps,
                              Step_Limited, Passed);
                           if Passed then
                              Enqueue (Node.Out_1);
                           end if;
                        end;

                     when Node_Lookbehind_Negative =>
                        declare
                           Passed : Boolean;
                        begin
                           Check_Lookbehind
                             (Expression, Node.Out_2, Node.Capture, Text, Position, Options, Steps,
                              Step_Limited, Passed);
                           if not Passed and then not Step_Limited then
                              Enqueue (Node.Out_1);
                           end if;
                        end;

                     when Node_Atomic =>
                        declare
                           Matched : Boolean;
                           End_Pos : Natural;
                        begin
                           Check_Atomic
                             (Expression, Node.Out_2, Text, Position, Options, Steps, Step_Limited,
                              Matched, End_Pos);
                           if Matched then
                              Add_State (Expression, Set, Node.Out_1, End_Pos, Text, Options, Steps, Step_Limited);
                           end if;
                        end;

                     when Node_Capture_Start | Node_Capture_End =>
                        Enqueue (Node.Out_1);

                     when others =>
                        null;
                  end case;
               end;
            end if;
         end;

         if Head = Default_Max_States then
            exit;
         end if;
         Head := Head + 1;
      end loop;
   end Add_State;

   function Relative_First (Text : String; Position : Natural) return Natural is
     (Relative_Offset (Text'First, Position));

   function Relative_Last (Text : String; Position : Natural) return Natural is
     (Relative_Offset (Text'First, Position));

   function Whole_Word_Passes
     (Text    : String;
      First   : Natural;
      Last    : Natural;
      Options : Match_Options)
      return Boolean
   is
      Next_Pos : Natural;
      Left_Ok  : Boolean;
      Right_Ok : Boolean;
   begin
      Left_Ok := True;
      if First > Nat (Text'First) and then First > Positive'First then
         if First - 1 <= Nat (Text'Last) then
            Left_Ok := not Is_Word (Text (Positive (First - 1)), Options.Character_Mode);
         end if;
      end if;

      if Last < First then
         Next_Pos := First;
      elsif Last = Natural'Last then
         Next_Pos := Natural'Last;
      else
         Next_Pos := Last + 1;
      end if;

      Right_Ok := True;
      if Next_Pos >= Nat (Text'First)
        and then Next_Pos <= Nat (Text'Last)
        and then Next_Pos >= Positive'First
      then
         Right_Ok := not Is_Word (Text (Positive (Next_Pos)), Options.Character_Mode);
      end if;
      return Left_Ok and then Right_Ok;
   end Whole_Word_Passes;

   function Has_Active (Set : Active_Set; Count : Natural) return Boolean is
   begin
      for I in 1 .. Count loop
         if Set (I) then
            return True;
         end if;
      end loop;

      return False;
   end Has_Active;

   type Capture_Set is array (Positive range 1 .. Max_Captures) of Text_Range;

   type Capture_Thread is record
      Active   : Boolean := False;
      Captures : Capture_Set := [others => <>];
   end record;

   type Capture_Thread_Set is array (Positive range 1 .. Default_Max_States) of Capture_Thread;

   procedure Match_Backreference
     (Node    : State;
      Text    : String;
      Pos     : Natural;
      Options : Match_Options;
      Captures : Capture_Set;
      Matched : out Boolean;
      Next_Pos : out Natural)
   is
      Capture_No : constant Natural := Node.Capture;
      First      : Natural;
      Last_R     : Natural;
      Source     : Natural;
      Target     : Natural := Pos;
   begin
      Matched := False;
      Next_Pos := Pos;

      if Capture_No not in 1 .. Max_Captures then
         return;
      end if;

      First := Captures (Positive (Capture_No)).First;
      Last_R := Captures (Positive (Capture_No)).Last;
      if First = 0 and then Last_R = 0 then
         return;
      elsif Last_R < First then
         Matched := True;
         return;
      end if;

      Source := Nat (Text'First) + First - 1;
      while Source <= Nat (Text'First) + Last_R - 1 loop
         pragma Loop_Variant (Increases => Source);
         if Target > Nat (Text'Last)
           or else not Equal_Chars
             (Text (Positive (Source)), Text (Positive (Target)), Effective_Case_Sensitive (Node, Options))
         then
            return;
         end if;
         Source := Source + 1;
         Target := Target + 1;
      end loop;

      Matched := True;
      Next_Pos := Target;
   end Match_Backreference;

   function Has_Active (Set : Capture_Thread_Set; Count : Natural) return Boolean is
   begin
      for I in 1 .. Count loop
         if Set (I).Active then
            return True;
         end if;
      end loop;

      return False;
   end Has_Active;

   procedure Add_Capture_State
     (Expression   : Regexp;
      Set          : in out Capture_Thread_Set;
      Index        : State_Index;
      Position     : Natural;
      Text         : String;
      Options      : Match_Options;
      Captures     : Capture_Set;
      Steps        : in out Natural;
      Step_Limited : in out Boolean)
   is
      Pending : array (Positive range 1 .. Default_Max_States) of State_Index := [others => No_State];
      Pending_Captures : array (Positive range 1 .. Default_Max_States) of Capture_Set := [others => [others => <>]];
      Head    : Positive := 1;
      Tail    : Natural := 0;

      procedure Enqueue (Candidate : State_Index; Candidate_Captures : Capture_Set) is
      begin
         if Step_Limited or else Candidate = No_State then
            return;
         end if;

         if Set (Positive (Candidate)).Active then
            return;
         end if;

         Consume_Step (Options, Steps, Step_Limited);
         if Step_Limited then
            return;
         end if;

         Set (Positive (Candidate)) := (Active => True, Captures => Candidate_Captures);
         if Tail < Default_Max_States then
            Tail := Tail + 1;
            Pending (Tail) := Candidate;
            Pending_Captures (Tail) := Candidate_Captures;
         else
            Step_Limited := True;
         end if;
      end Enqueue;
   begin
      Enqueue (Index, Captures);

      while Head <= Tail loop
         pragma Loop_Invariant (Head in 1 .. Default_Max_States);
         pragma Loop_Invariant (Tail <= Default_Max_States);
         pragma Loop_Variant (Increases => Head);

         declare
            Current : constant State_Index := Pending (Head);
            Current_Captures : Capture_Set := Pending_Captures (Head);
         begin
            if Current /= No_State then
               declare
                  Node : State renames Expression.States (Positive (Current));
               begin
                  case Node.Kind is
                     when Node_Split =>
                        Enqueue (Node.Out_1, Current_Captures);
                        Enqueue (Node.Out_2, Current_Captures);

                     when Node_Start_Line =>
                        if Position = Nat (Text'First)
                          or else
                            (Effective_Multiline_Anchors (Node, Options)
                             and then Position > Nat (Text'First)
                             and then Position <= Nat (Text'Last) + 1
                             and then
                               (Text (Positive (Position - 1)) = Character'Val (10)
                                or else Text (Positive (Position - 1)) = Character'Val (13)))
                        then
                           Enqueue (Node.Out_1, Current_Captures);
                        end if;

                     when Node_End_Line =>
                        if Position > Nat (Text'Last)
                          or else
                            (Effective_Multiline_Anchors (Node, Options)
                             and then Position <= Nat (Text'Last)
                             and then
                               (Text (Positive (Position)) = Character'Val (10)
                                or else Text (Positive (Position)) = Character'Val (13)))
                        then
                           Enqueue (Node.Out_1, Current_Captures);
                        end if;

                     when Node_Word_Boundary =>
                        if Word_Boundary_Passes (Text, Position, Options) then
                           Enqueue (Node.Out_1, Current_Captures);
                        end if;

                     when Node_Not_Word_Boundary =>
                        if not Word_Boundary_Passes (Text, Position, Options) then
                           Enqueue (Node.Out_1, Current_Captures);
                        end if;

                     when Node_Lookahead_Positive =>
                        declare
                           Passed : Boolean;
                        begin
                           Check_Lookahead
                             (Expression, Node.Out_2, Text, Position, Options, Steps, Step_Limited, Passed);
                           if Passed then
                              Enqueue (Node.Out_1, Current_Captures);
                           end if;
                        end;

                     when Node_Lookahead_Negative =>
                        declare
                           Passed : Boolean;
                        begin
                           Check_Lookahead
                             (Expression, Node.Out_2, Text, Position, Options, Steps, Step_Limited, Passed);
                           if not Passed and then not Step_Limited then
                              Enqueue (Node.Out_1, Current_Captures);
                           end if;
                        end;

                     when Node_Lookbehind_Positive =>
                        declare
                           Passed : Boolean;
                        begin
                           Check_Lookbehind
                             (Expression, Node.Out_2, Node.Capture, Text, Position, Options, Steps,
                              Step_Limited, Passed);
                           if Passed then
                              Enqueue (Node.Out_1, Current_Captures);
                           end if;
                        end;

                     when Node_Lookbehind_Negative =>
                        declare
                           Passed : Boolean;
                        begin
                           Check_Lookbehind
                             (Expression, Node.Out_2, Node.Capture, Text, Position, Options, Steps,
                              Step_Limited, Passed);
                           if not Passed and then not Step_Limited then
                              Enqueue (Node.Out_1, Current_Captures);
                           end if;
                        end;

                     when Node_Atomic =>
                        declare
                           Matched : Boolean;
                           End_Pos : Natural;
                        begin
                           Check_Atomic
                             (Expression, Node.Out_2, Text, Position, Options, Steps, Step_Limited,
                              Matched, End_Pos);
                           if Matched then
                              Add_Capture_State
                                (Expression, Set, Node.Out_1, End_Pos, Text, Options,
                                 Current_Captures, Steps, Step_Limited);
                           end if;
                        end;

                     when Node_Capture_Start =>
                        if Node.Capture in 1 .. Max_Captures then
                           Current_Captures (Positive (Node.Capture)).First :=
                             Relative_Offset (Text'First, Position);
                        end if;
                        Enqueue (Node.Out_1, Current_Captures);

                     when Node_Capture_End =>
                        if Node.Capture in 1 .. Max_Captures then
                           Current_Captures (Positive (Node.Capture)).Last :=
                             (if Position = 0 then 0 else Relative_Offset (Text'First, Position - 1));
                        end if;
                        Enqueue (Node.Out_1, Current_Captures);

                     when others =>
                        null;
                  end case;
               end;
            end if;
         end;

         if Head = Default_Max_States then
            exit;
         end if;
         Head := Head + 1;
      end loop;
   end Add_Capture_State;

   procedure Run_From_With_Captures
     (Expression  : Regexp;
      Text        : String;
      Start_Pos   : Positive;
      Require_End : Boolean;
      Options     : Match_Options;
      Found       : out Match_Result;
      Captures    : out Capture_Set)
      with Pre => Text'Last < Positive'Last
   is
      Current      : Capture_Thread_Set := [others => <>];
      Next         : Capture_Thread_Set;
      Empty        : constant Capture_Set := [others => <>];
      Steps        : Natural := 0;
      Step_Limited : Boolean := False;
      Pos          : Natural := Start_Pos;
      W            : Positive := 1;   --  width in bytes of the input unit at Pos
      Matched      : Boolean;
      Best_Matched : Boolean := False;
      Best_Last    : Natural := 0;
      Best_Captures : Capture_Set := [others => <>];
      Node         : State;
      Last         : Natural;
      Backref_Ok   : Boolean;
      Backref_Next : Natural;
   begin
      Captures := [others => <>];
      if not Expression.Valid then
         Found := (Status => Invalid_Regexp, others => <>);
         return;
      end if;

      if Pos < Nat (Text'First) or else Pos > Nat (Text'Last) + 1 then
         Found := (Status => No_Match, others => <>);
         return;
      end if;

      Add_Capture_State (Expression, Current, Expression.Start, Pos, Text, Options, Empty, Steps, Step_Limited);
      if Step_Limited then
         Found := (Status => Match_Limit_Exceeded, Steps_Used => Steps, others => <>);
         return;
      end if;

      loop
         pragma Loop_Invariant (Pos >= Nat (Text'First));
         pragma Loop_Invariant (Pos >= Positive'First);
         pragma Loop_Invariant (Pos <= Nat (Text'Last) + 1);
         pragma Loop_Variant (Increases => Pos);

         Matched := False;
         for I in 1 .. Expression.State_Count loop
            if Current (I).Active and then Expression.States (I).Kind = Node_Match then
               Matched := True;
               Best_Captures := Current (I).Captures;
            end if;
         end loop;

         if Matched and then (not Require_End or else Pos > Nat (Text'Last)) then
            Last := (if Pos = 0 then 0 else Pos - 1);
            if not Options.Whole_Word or else Whole_Word_Passes (Text, Start_Pos, Last, Options) then
               Best_Matched := True;
               Best_Last := Last;
               Captures := Best_Captures;
               if Expression.Prefer_First_Match then
                  Found :=
                    (Status     => Match_Ok,
                     First      => Relative_First (Text, Start_Pos),
                     Last       => Relative_Last (Text, Best_Last),
                     Steps_Used => Steps);
                  return;
               end if;
            end if;
         end if;

         exit when Pos > Nat (Text'Last);
         W := Step_Width (Expression, Text, Positive (Pos));

         Next := [others => <>];
         for I in 1 .. Expression.State_Count loop
            if Current (I).Active then
               Node := Expression.States (I);
               Consume_Step (Options, Steps, Step_Limited);
               if Step_Limited then
                  Found := (Status => Match_Limit_Exceeded, Steps_Used => Steps, others => <>);
                  return;
               end if;

               case Node.Kind is
                  when Node_Char =>
                     if Equal_Chars
                         (Node.Ch, Text (Positive (Pos)), Effective_Case_Sensitive (Node, Options))
                     then
                        Add_Capture_State
                          (Expression, Next, Node.Out_1,
                           Pos + W, Text, Options,
                           Current (I).Captures, Steps, Step_Limited);
                     end if;

                  when Node_Any =>
                     if Effective_Dot_Matches_Newline (Node, Options)
                       or else
                         (Text (Positive (Pos)) /= Character'Val (10)
                          and then Text (Positive (Pos)) /= Character'Val (13))
                     then
                        Add_Capture_State
                          (Expression, Next, Node.Out_1,
                           Pos + W, Text, Options,
                           Current (I).Captures, Steps, Step_Limited);
                     end if;

                  when Node_Class =>
                     if Class_Matches
                         (Expression, Node, Text, Positive (Pos), Effective_Case_Sensitive (Node, Options))
                     then
                        Add_Capture_State
                          (Expression, Next, Node.Out_1,
                           Pos + W, Text, Options,
                           Current (I).Captures, Steps, Step_Limited);
                     end if;

                  when Node_Backreference =>
                     Match_Backreference
                       (Node, Text, Pos, Options, Current (I).Captures, Backref_Ok, Backref_Next);
                     if Backref_Ok then
                        Add_Capture_State
                          (Expression, Next, Node.Out_1, Backref_Next, Text, Options,
                           Current (I).Captures, Steps, Step_Limited);
                     end if;

                  when others =>
                     null;
               end case;

               if Step_Limited then
                  Found := (Status => Match_Limit_Exceeded, Steps_Used => Steps, others => <>);
                  return;
               end if;
            end if;
         end loop;

         if not Has_Active (Next, Expression.State_Count) then
            exit;
         end if;

         Current := Next;
         Pos := Pos + W;
      end loop;

      if Best_Matched then
         Found :=
           (Status     => Match_Ok,
            First      => Relative_First (Text, Start_Pos),
            Last       => Relative_Last (Text, Best_Last),
            Steps_Used => Steps);
         return;
      end if;

      Found := (Status => No_Match, Steps_Used => Steps, others => <>);
   end Run_From_With_Captures;

   --  Recursion depth at which a backtracking match gives up.
   --
   --  Depth grows with the number of input units one candidate path consumes,
   --  so a pattern such as \(a*\)\1 over a long span can nest deeply. Running
   --  out of stack would be a crash; stopping here is a determinate
   --  Match_Limit_Exceeded that the caller already knows how to report. The
   --  value leaves room for spans far longer than any realistic
   --  backreferenced pattern matches, while keeping worst-case stack use to a
   --  few megabytes.
   Max_Backtrack_Depth : constant Positive := 20_000;

   --  Match by backtracking, carrying captures along each candidate path.
   --
   --  A backreference is not a regular construct: what it matches depends on
   --  what an earlier group captured on the same path, so its width is not
   --  known until that path is taken. The lock-step simulation used elsewhere
   --  advances every live thread by one input unit at a time and therefore
   --  cannot represent it -- a backreference thread would be treated as
   --  having consumed a single unit whatever it actually matched.
   --
   --  This walker instead explores one path at a time with its own position
   --  and its own capture set, which is what lets a backreference consume the
   --  whole captured span. It is used only when the expression really
   --  contains a backreference; every other pattern keeps the linear-time
   --  path, so the cost of backtracking is confined to the feature that
   --  requires it.
   procedure Run_From_Backtracking
     (Expression  : Regexp;
      Text        : String;
      Start_Pos   : Positive;
      Require_End : Boolean;
      Options     : Match_Options;
      Found       : out Match_Result;
      Captures    : out Capture_Set)
      with Pre => Text'Last < Positive'Last
   is
      Steps         : Natural := 0;
      Step_Limited  : Boolean := False;
      Best_Matched  : Boolean := False;
      Best_Last     : Natural := 0;
      Best_Captures : Capture_Set := [others => <>];
      Live          : Capture_Set := [others => <>];

      --  Explore one path. Live carries the captures recorded so far; a
      --  capture node changes one field, explores, and puts the old value
      --  back, so a path that fails leaves nothing behind for its sibling.
      procedure Explore (Index : State_Index; Position : Natural; Depth : Positive);

      -------------
      -- Explore --
      -------------

      procedure Explore (Index : State_Index; Position : Natural; Depth : Positive) is
         Passed : Boolean;
      begin
         if Step_Limited or else Index = No_State then
            return;
         end if;

         if Depth >= Max_Backtrack_Depth then
            Step_Limited := True;
            return;
         end if;

         Consume_Step (Options, Steps, Step_Limited);
         if Step_Limited then
            return;
         end if;

         declare
            Node : State renames Expression.States (Positive (Index));
         begin
            case Node.Kind is
               when Node_Match =>
                  if not Require_End or else Position > Nat (Text'Last) then
                     declare
                        Last : constant Natural :=
                          (if Position = 0 then 0 else Position - 1);
                     begin
                        if not Options.Whole_Word
                          or else Whole_Word_Passes (Text, Start_Pos, Last, Options)
                        then
                           if not Best_Matched
                             or else Last > Best_Last
                             or else Expression.Prefer_First_Match
                           then
                              Best_Matched := True;
                              Best_Last := Last;
                              Best_Captures := Live;
                           end if;
                        end if;
                     end;
                  end if;

               when Node_Split =>
                  Explore (Node.Out_1, Position, Depth + 1);
                  if not Expression.Prefer_First_Match or else not Best_Matched then
                     Explore (Node.Out_2, Position, Depth + 1);
                  end if;

               when Node_Start_Line =>
                  if Position = Nat (Text'First)
                    or else
                      (Effective_Multiline_Anchors (Node, Options)
                       and then Position > Nat (Text'First)
                       and then Position <= Nat (Text'Last) + 1
                       and then
                         (Text (Positive (Position - 1)) = Character'Val (10)
                          or else Text (Positive (Position - 1)) = Character'Val (13)))
                  then
                     Explore (Node.Out_1, Position, Depth + 1);
                  end if;

               when Node_End_Line =>
                  if Position > Nat (Text'Last)
                    or else
                      (Effective_Multiline_Anchors (Node, Options)
                       and then Position <= Nat (Text'Last)
                       and then
                         (Text (Positive (Position)) = Character'Val (10)
                          or else Text (Positive (Position)) = Character'Val (13)))
                  then
                     Explore (Node.Out_1, Position, Depth + 1);
                  end if;

               when Node_Word_Boundary =>
                  if Word_Boundary_Passes (Text, Position, Options) then
                     Explore (Node.Out_1, Position, Depth + 1);
                  end if;

               when Node_Not_Word_Boundary =>
                  if not Word_Boundary_Passes (Text, Position, Options) then
                     Explore (Node.Out_1, Position, Depth + 1);
                  end if;

               when Node_Lookahead_Positive =>
                  Check_Lookahead
                    (Expression, Node.Out_2, Text, Position, Options, Steps, Step_Limited, Passed);
                  if Passed then
                     Explore (Node.Out_1, Position, Depth + 1);
                  end if;

               when Node_Lookahead_Negative =>
                  Check_Lookahead
                    (Expression, Node.Out_2, Text, Position, Options, Steps, Step_Limited, Passed);
                  if not Passed and then not Step_Limited then
                     Explore (Node.Out_1, Position, Depth + 1);
                  end if;

               when Node_Lookbehind_Positive =>
                  Check_Lookbehind
                    (Expression, Node.Out_2, Node.Capture, Text, Position, Options,
                     Steps, Step_Limited, Passed);
                  if Passed then
                     Explore (Node.Out_1, Position, Depth + 1);
                  end if;

               when Node_Lookbehind_Negative =>
                  Check_Lookbehind
                    (Expression, Node.Out_2, Node.Capture, Text, Position, Options,
                     Steps, Step_Limited, Passed);
                  if not Passed and then not Step_Limited then
                     Explore (Node.Out_1, Position, Depth + 1);
                  end if;

               when Node_Char =>
                  if Position <= Nat (Text'Last)
                    and then Equal_Chars
                      (Node.Ch, Text (Positive (Position)),
                       Effective_Case_Sensitive (Node, Options))
                  then
                     Explore
                       (Node.Out_1,
                        Position + Step_Width (Expression, Text, Positive (Position)),
                        Depth + 1);
                  end if;

               when Node_Any =>
                  if Position <= Nat (Text'Last)
                    and then
                      (Effective_Dot_Matches_Newline (Node, Options)
                       or else
                         (Text (Positive (Position)) /= Character'Val (10)
                          and then Text (Positive (Position)) /= Character'Val (13)))
                  then
                     Explore
                       (Node.Out_1,
                        Position + Step_Width (Expression, Text, Positive (Position)),
                        Depth + 1);
                  end if;

               when Node_Class =>
                  if Position <= Nat (Text'Last)
                    and then Class_Matches
                      (Expression, Node, Text, Positive (Position),
                       Effective_Case_Sensitive (Node, Options))
                  then
                     Explore
                       (Node.Out_1,
                        Position + Step_Width (Expression, Text, Positive (Position)),
                        Depth + 1);
                  end if;

               when Node_Capture_Start =>
                  if Node.Capture in 1 .. Max_Captures then
                     declare
                        Slot : Text_Range renames Live (Positive (Node.Capture));
                        Saved : constant Natural := Slot.First;
                     begin
                        Slot.First := Relative_Offset (Text'First, Position);
                        Explore (Node.Out_1, Position, Depth + 1);
                        Slot.First := Saved;
                     end;
                  else
                     Explore (Node.Out_1, Position, Depth + 1);
                  end if;

               when Node_Capture_End =>
                  if Node.Capture in 1 .. Max_Captures then
                     declare
                        Slot : Text_Range renames Live (Positive (Node.Capture));
                        Saved : constant Natural := Slot.Last;
                     begin
                        Slot.Last :=
                          (if Position = 0
                           then 0
                           else Relative_Offset (Text'First, Position - 1));
                        Explore (Node.Out_1, Position, Depth + 1);
                        Slot.Last := Saved;
                     end;
                  else
                     Explore (Node.Out_1, Position, Depth + 1);
                  end if;

               when Node_Backreference =>
                  declare
                     Backref_Ok   : Boolean;
                     Backref_Next : Natural;
                  begin
                     --  The captured span is known on this path, so the
                     --  reference consumes exactly as much text as it names.
                     Match_Backreference
                       (Node, Text, Position, Options, Live, Backref_Ok, Backref_Next);
                     if Backref_Ok then
                        Explore (Node.Out_1, Backref_Next, Depth + 1);
                     end if;
                  end;

               when others =>
                  null;
            end case;
         end;
      end Explore;

   begin
      Captures := [others => <>];

      if not Expression.Valid then
         Found := (Status => Invalid_Regexp, others => <>);
         return;
      elsif Start_Pos < Nat (Text'First) or else Start_Pos > Nat (Text'Last) + 1 then
         Found := (Status => No_Match, others => <>);
         return;
      end if;

      Explore (Expression.Start, Start_Pos, 1);

      if Step_Limited then
         Found := (Status => Match_Limit_Exceeded, Steps_Used => Steps, others => <>);
      elsif Best_Matched then
         Captures := Best_Captures;
         Found :=
           (Status     => Match_Ok,
            First      => Relative_First (Text, Start_Pos),
            Last       => Relative_Last (Text, Best_Last),
            Steps_Used => Steps);
      else
         Found := (Status => No_Match, Steps_Used => Steps, others => <>);
      end if;
   end Run_From_Backtracking;

   function Run_From_Atomic
     (Expression  : Regexp;
      Text        : String;
      Start_Pos   : Positive;
      Require_End : Boolean;
      Options     : Match_Options)
      return Match_Result
      with Pre => Text'Last < Positive'Last
   is
      Steps        : Natural := 0;
      Step_Limited : Boolean := False;
      Best_Matched : Boolean := False;
      Best_Last    : Natural := 0;

      procedure Explore (Index : State_Index; Position : Natural) is
         Node       : State;
         Passed     : Boolean;
         Atomic_Ok  : Boolean;
         Atomic_End : Natural;
      begin
         if Step_Limited or else Index = No_State then
            return;
         end if;

         Consume_Step (Options, Steps, Step_Limited);
         if Step_Limited then
            return;
         end if;

         Node := Expression.States (Positive (Index));
         case Node.Kind is
            when Node_Match =>
               if not Require_End or else Position > Nat (Text'Last) then
                  declare
                     Last : constant Natural := (if Position = 0 then 0 else Position - 1);
                  begin
                     if not Options.Whole_Word or else Whole_Word_Passes (Text, Start_Pos, Last, Options) then
                        if not Best_Matched or else Last > Best_Last or else Expression.Prefer_First_Match then
                           Best_Matched := True;
                           Best_Last := Last;
                        end if;
                     end if;
                  end;
               end if;

            when Node_Split =>
               Explore (Node.Out_1, Position);
               if not Expression.Prefer_First_Match or else not Best_Matched then
                  Explore (Node.Out_2, Position);
               end if;

            when Node_Start_Line =>
               if Position = Nat (Text'First)
                 or else
                   (Effective_Multiline_Anchors (Node, Options)
                    and then Position > Nat (Text'First)
                    and then Position <= Nat (Text'Last) + 1
                    and then
                      (Text (Positive (Position - 1)) = Character'Val (10)
                       or else Text (Positive (Position - 1)) = Character'Val (13)))
               then
                  Explore (Node.Out_1, Position);
               end if;

            when Node_End_Line =>
               if Position > Nat (Text'Last)
                 or else
                   (Effective_Multiline_Anchors (Node, Options)
                    and then Position <= Nat (Text'Last)
                    and then
                      (Text (Positive (Position)) = Character'Val (10)
                       or else Text (Positive (Position)) = Character'Val (13)))
               then
                  Explore (Node.Out_1, Position);
               end if;

            when Node_Word_Boundary =>
               if Word_Boundary_Passes (Text, Position, Options) then
                  Explore (Node.Out_1, Position);
               end if;

            when Node_Not_Word_Boundary =>
               if not Word_Boundary_Passes (Text, Position, Options) then
                  Explore (Node.Out_1, Position);
               end if;

            when Node_Lookahead_Positive =>
               Check_Lookahead
                 (Expression, Node.Out_2, Text, Position, Options, Steps, Step_Limited, Passed);
               if Passed then
                  Explore (Node.Out_1, Position);
               end if;

            when Node_Lookahead_Negative =>
               Check_Lookahead
                 (Expression, Node.Out_2, Text, Position, Options, Steps, Step_Limited, Passed);
               if not Passed and then not Step_Limited then
                  Explore (Node.Out_1, Position);
               end if;

            when Node_Lookbehind_Positive =>
               Check_Lookbehind
                 (Expression, Node.Out_2, Node.Capture, Text, Position, Options, Steps, Step_Limited, Passed);
               if Passed then
                  Explore (Node.Out_1, Position);
               end if;

            when Node_Lookbehind_Negative =>
               Check_Lookbehind
                 (Expression, Node.Out_2, Node.Capture, Text, Position, Options, Steps, Step_Limited, Passed);
               if not Passed and then not Step_Limited then
                  Explore (Node.Out_1, Position);
               end if;

            when Node_Atomic =>
               Check_Atomic
                 (Expression, Node.Out_2, Text, Position, Options, Steps, Step_Limited, Atomic_Ok, Atomic_End);
               if Atomic_Ok then
                  Explore (Node.Out_1, Atomic_End);
               end if;

            when Node_Char =>
               if Position <= Nat (Text'Last)
                 and then Equal_Chars
                   (Node.Ch, Text (Positive (Position)), Effective_Case_Sensitive (Node, Options))
               then
                  Explore (Node.Out_1, Position + Step_Width (Expression, Text, Positive (Position)));
               end if;

            when Node_Any =>
               if Position <= Nat (Text'Last)
                 and then
                   (Effective_Dot_Matches_Newline (Node, Options)
                    or else
                      (Text (Positive (Position)) /= Character'Val (10)
                       and then Text (Positive (Position)) /= Character'Val (13)))
               then
                  Explore (Node.Out_1, Position + Step_Width (Expression, Text, Positive (Position)));
               end if;

            when Node_Class =>
               if Position <= Nat (Text'Last)
                 and then Class_Matches
                   (Expression, Node, Text, Positive (Position), Effective_Case_Sensitive (Node, Options))
               then
                  Explore (Node.Out_1, Position + Step_Width (Expression, Text, Positive (Position)));
               end if;

            when others =>
               null;
         end case;
      end Explore;
   begin
      if not Expression.Valid then
         return (Status => Invalid_Regexp, others => <>);
      elsif Start_Pos < Nat (Text'First) or else Start_Pos > Nat (Text'Last) + 1 then
         return (Status => No_Match, others => <>);
      end if;

      Explore (Expression.Start, Start_Pos);
      if Step_Limited then
         return (Status => Match_Limit_Exceeded, Steps_Used => Steps, others => <>);
      elsif Best_Matched then
         return
           (Status     => Match_Ok,
            First      => Relative_First (Text, Start_Pos),
            Last       => Relative_Last (Text, Best_Last),
            Steps_Used => Steps);
      else
         return (Status => No_Match, Steps_Used => Steps, others => <>);
      end if;
   end Run_From_Atomic;

   function Run_From
     (Expression  : Regexp;
      Text        : String;
      Start_Pos   : Positive;
      Require_End : Boolean;
      Options     : Match_Options)
      return Match_Result
      with Pre => Text'Last < Positive'Last
   is
      Current      : Active_Set := [others => False];
      Next         : Active_Set;
      Steps        : Natural := 0;
      Step_Limited : Boolean := False;
      Pos          : Natural := Start_Pos;
      W            : Positive := 1;   --  width in bytes of the input unit at Pos
      Matched      : Boolean;
      Best_Matched : Boolean := False;
      Best_Last    : Natural := 0;
      Node         : State;
      Last         : Natural;
      Capture_Found : Match_Result;
      Capture_Set_Value : Capture_Set := [others => <>];
   begin
      if not Expression.Valid then
         return (Status => Invalid_Regexp, others => <>);
      end if;

      if Expression.Has_Atomic then
         return Run_From_Atomic (Expression, Text, Start_Pos, Require_End, Options);
      end if;

      if Expression.Has_Backreferences then
         --  A backreference consumes what an earlier group captured on the
         --  same path, which only a backtracking walk can represent.
         Run_From_Backtracking
           (Expression, Text, Start_Pos, Require_End, Options, Capture_Found, Capture_Set_Value);
         return Capture_Found;
      end if;

      if Pos < Nat (Text'First) or else Pos > Nat (Text'Last) + 1 then
         return (Status => No_Match, others => <>);
      end if;

      Add_State (Expression, Current, Expression.Start, Pos, Text, Options, Steps, Step_Limited);
      if Step_Limited then
         return (Status => Match_Limit_Exceeded, Steps_Used => Steps, others => <>);
      end if;

      loop
         pragma Loop_Invariant (Pos >= Nat (Text'First));
         pragma Loop_Invariant (Pos >= Positive'First);
         pragma Loop_Invariant (Pos <= Nat (Text'Last) + 1);
         pragma Loop_Variant (Increases => Pos);

         Matched := False;
         for I in 1 .. Expression.State_Count loop
            if Current (I) and then Expression.States (I).Kind = Node_Match then
               Matched := True;
            end if;
         end loop;

         if Matched and then (not Require_End or else Pos > Nat (Text'Last)) then
            if Pos = 0 then
               Last := 0;
            else
               Last := Pos - 1;
            end if;
            if not Options.Whole_Word or else Whole_Word_Passes (Text, Start_Pos, Last, Options) then
               Best_Matched := True;
               Best_Last := Last;
               if Expression.Prefer_First_Match then
                  return
                    (Status     => Match_Ok,
                     First      => Relative_First (Text, Start_Pos),
                     Last       => Relative_Last (Text, Best_Last),
                     Steps_Used => Steps);
               end if;
            end if;
         end if;

         exit when Pos > Nat (Text'Last);
         W := Step_Width (Expression, Text, Positive (Pos));

         Next := [others => False];
         for I in 1 .. Expression.State_Count loop
            if Current (I) then
               Node := Expression.States (I);
               Consume_Step (Options, Steps, Step_Limited);
               if Step_Limited then
                  return (Status => Match_Limit_Exceeded, Steps_Used => Steps, others => <>);
               end if;

               case Node.Kind is
                  when Node_Char =>
                     if Equal_Chars
                         (Node.Ch, Text (Positive (Pos)), Effective_Case_Sensitive (Node, Options))
                     then
                        Add_State (Expression, Next, Node.Out_1, Pos + W, Text, Options, Steps, Step_Limited);
                     end if;

                  when Node_Any =>
                     if Effective_Dot_Matches_Newline (Node, Options)
                       or else
                         (Text (Positive (Pos)) /= Character'Val (10)
                          and then Text (Positive (Pos)) /= Character'Val (13))
                     then
                        Add_State (Expression, Next, Node.Out_1, Pos + W, Text, Options, Steps, Step_Limited);
                     end if;

                  when Node_Class =>
                     if Class_Matches
                         (Expression, Node, Text, Positive (Pos), Effective_Case_Sensitive (Node, Options))
                     then
                        Add_State (Expression, Next, Node.Out_1, Pos + W, Text, Options, Steps, Step_Limited);
                     end if;

                  when others =>
                     null;
               end case;

               if Step_Limited then
                  return (Status => Match_Limit_Exceeded, Steps_Used => Steps, others => <>);
               end if;
            end if;
         end loop;

         if not Has_Active (Next, Expression.State_Count) then
            exit;
         end if;

         Current := Next;
         Pos := Pos + W;
      end loop;

      if Best_Matched then
         return
           (Status     => Match_Ok,
            First      => Relative_First (Text, Start_Pos),
            Last       => Relative_Last (Text, Best_Last),
            Steps_Used => Steps);
      end if;

      return (Status => No_Match, Steps_Used => Steps, others => <>);
   end Run_From;

   function Find_First
     (Expression : Regexp;
      Text       : String;
      Options    : Match_Options := (others => <>))
      return Match_Result
   is
   begin
      return Find_From (Expression, Text, 1, Options);
   end Find_First;

   procedure Find_First_With_Captures
     (Expression : Regexp;
      Text       : String;
      Found      : out Match_Result;
      Captures   : out Text_Range_Array;
      Count      : out Natural;
      Options    : Match_Options := (others => <>))
   is
   begin
      Find_From_With_Captures (Expression, Text, 1, Found, Captures, Count, Options);
   end Find_First_With_Captures;

   function Find_From
     (Expression : Regexp;
      Text       : String;
      From       : Positive;
      Options    : Match_Options := (others => <>))
      return Match_Result
   is
      Result      : Match_Result;
      Start       : Positive;
      Total_Steps : Natural := 0;
      Remaining   : Natural;
      Run_Options : Match_Options := Options;
      UTF_8        : UTF_8_Validation_Result;
   begin
      if not Expression.Valid then
         return (Status => Invalid_Regexp, others => <>);
      end if;

      if Options.Character_Mode = UTF_8_Mode then
         UTF_8 := Validate_UTF_8 (Text);
         if not UTF_8.Valid then
            return (Status => No_Match, others => <>);
         end if;
      end if;

      if From > Text'Length + 1 then
         return (Status => No_Match, others => <>);
      end if;

      if From - 1 > Positive'Last - Nat (Text'First) then
         return (Status => No_Match, others => <>);
      end if;

      Start := Pos_Or_First (Nat (Text'First) + (From - 1));
      while Start <= Nat (Text'Last) + 1 loop
         pragma Loop_Variant (Increases => Start);

         if Total_Steps >= Options.Max_Steps then
            return (Status => Match_Limit_Exceeded, Steps_Used => Total_Steps, others => <>);
         end if;

         Remaining := Options.Max_Steps - Total_Steps;
         Run_Options.Max_Steps := Remaining;
         Result := Run_From (Expression, Text, Start, False, Run_Options);
         if Result.Steps_Used > Natural'Last - Total_Steps then
            return (Status => Match_Limit_Exceeded, Steps_Used => Total_Steps, others => <>);
         end if;
         Total_Steps := Total_Steps + Result.Steps_Used;

         if Result.Status = Match_Ok then
            Result.Steps_Used := Total_Steps;
            return Result;
         elsif Result.Status = Match_Limit_Exceeded then
            return (Status => Match_Limit_Exceeded, Steps_Used => Total_Steps, others => <>);
         end if;

         exit when Start > Nat (Text'Last);
         Start := Start + 1;
      end loop;

      return (Status => No_Match, Steps_Used => Total_Steps, others => <>);
   end Find_From;

   function Find_From_Planned
     (Expression : Regexp;
      Text       : String;
      From       : Positive := 1;
      Options    : Match_Options := (others => <>))
      return Match_Result
   is
      Prefix : String (1 .. Default_Max_Pattern_Length);
      Last   : Natural;
      Status : Copy_Status;
      Start  : Positive := From;

      function Prefix_At (Offset : Positive) return Boolean is
      begin
         if Last = 0 then
            return True;
         elsif Offset > Text'Length or else Offset + Last - 1 > Text'Length then
            return False;
         end if;

         for I in 1 .. Last loop
            if not Equal_Chars
              (Text (Text'First + Offset + I - 2), Prefix (I), Options.Case_Sensitive)
            then
               return False;
            end if;
         end loop;

         return True;
      end Prefix_At;
   begin
      Required_Prefix (Expression, Prefix, Last, Status);
      if Status /= Copy_Ok or else Last = 0 or else From > Text'Length then
         return Find_From (Expression, Text, From, Options);
      end if;

      while Start <= Text'Length loop
         if Prefix_At (Start) then
            declare
               Found : constant Match_Result := Find_From (Expression, Text, Start, Options);
            begin
               if Found.Status /= Match_Ok or else Found.First = Start then
                  return Found;
               elsif Found.First > Start then
                  Start := Found.First;
               else
                  return Found;
               end if;
            end;
         elsif Start = Positive'Last then
            exit;
         else
            Start := Start + 1;
         end if;
      end loop;

      return (Status => No_Match, others => <>);
   end Find_From_Planned;

   procedure Find_From_Planned_With_Captures
     (Expression : Regexp;
      Text       : String;
      From       : Positive;
      Found      : out Match_Result;
      Captures   : out Text_Range_Array;
      Count      : out Natural;
      Options    : Match_Options := (others => <>))
   is
      Planned : constant Match_Result := Find_From_Planned (Expression, Text, From, Options);
   begin
      Captures := [others => (First => 0, Last => 0)];
      Count := 0;

      if Planned.Status = Match_Ok then
         Find_From_With_Captures (Expression, Text, Planned.First, Found, Captures, Count, Options);
         if Found.Status = Match_Ok and then Found.First /= Planned.First then
            Found := Planned;
            Count := 0;
            Captures := [others => (First => 0, Last => 0)];
         end if;
      else
         Found := Planned;
      end if;
   end Find_From_Planned_With_Captures;

   procedure Find_From_With_Captures
     (Expression : Regexp;
      Text       : String;
      From       : Positive;
      Found      : out Match_Result;
      Captures   : out Text_Range_Array;
      Count      : out Natural;
      Options    : Match_Options := (others => <>))
   is
      Local_Captures : Capture_Set := [others => <>];
      Start          : Positive;
      Total_Steps    : Natural := 0;
      Remaining      : Natural;
      Run_Options    : Match_Options := Options;
      UTF_8           : UTF_8_Validation_Result;
   begin
      Captures := [others => <>];
      Count := 0;

      if not Expression.Valid then
         Found := (Status => Invalid_Regexp, others => <>);
         return;
      end if;

      if Options.Character_Mode = UTF_8_Mode then
         UTF_8 := Validate_UTF_8 (Text);
         if not UTF_8.Valid then
            Found := (Status => No_Match, others => <>);
            return;
         end if;
      end if;

      Count := Natural'Min (Expression.Capture_Count, Captures'Length);
      if Text'Length = 0 then
         if From > 1 then
            Found := (Status => No_Match, others => <>);
            return;
         end if;
      elsif From > Text'Length + 1 then
         Found := (Status => No_Match, others => <>);
         return;
      end if;

      if From - 1 > Positive'Last - Nat (Text'First) then
         Found := (Status => No_Match, others => <>);
         return;
      end if;

      Start := Pos_Or_First (Nat (Text'First) + (From - 1));
      while Start <= Nat (Text'Last) + 1 loop
         pragma Loop_Variant (Increases => Start);

         if Total_Steps >= Options.Max_Steps then
            Found := (Status => Match_Limit_Exceeded, Steps_Used => Total_Steps, others => <>);
            return;
         end if;

         Remaining := Options.Max_Steps - Total_Steps;
         Run_Options.Max_Steps := Remaining;
         if Expression.Has_Atomic then
            Found := Run_From_Atomic (Expression, Text, Start, False, Run_Options);
            Local_Captures := [others => <>];
         elsif Expression.Has_Backreferences then
            Run_From_Backtracking
              (Expression, Text, Start, False, Run_Options, Found, Local_Captures);
         else
            Run_From_With_Captures (Expression, Text, Start, False, Run_Options, Found, Local_Captures);
         end if;

         if Found.Steps_Used > Natural'Last - Total_Steps then
            Found := (Status => Match_Limit_Exceeded, Steps_Used => Total_Steps, others => <>);
            return;
         end if;
         Total_Steps := Total_Steps + Found.Steps_Used;

         if Found.Status = Match_Ok then
            Found.Steps_Used := Total_Steps;
            for I in 1 .. Count loop
               Captures (Captures'First + I - 1) := Local_Captures (I);
            end loop;
            return;
         elsif Found.Status = Match_Limit_Exceeded then
            Found := (Status => Match_Limit_Exceeded, Steps_Used => Total_Steps, others => <>);
            return;
         end if;

         exit when Start > Nat (Text'Last);
         Start := Start + 1;
      end loop;

      Found := (Status => No_Match, Steps_Used => Total_Steps, others => <>);
   end Find_From_With_Captures;

   procedure Find_All
     (Expression : Regexp;
      Text       : String;
      Matches    : out Match_Result_Array;
      Count      : out Natural;
      Status     : out Find_All_Status;
      Options    : Match_Options := (others => <>))
   is
   begin
      Find_All_From (Expression, Text, 1, Matches, Count, Status, Options);
   end Find_All;

   procedure Find_All_With_Captures
     (Expression    : Regexp;
      Text          : String;
      Matches       : out Match_Result_Array;
      Captures      : out Capture_Result_Array;
      Count         : out Natural;
      Capture_Count : out Natural;
      Status        : out Find_All_Status;
      Options       : Match_Options := (others => <>))
   is
   begin
      Find_All_With_Captures_From (Expression, Text, 1, Matches, Captures, Count, Capture_Count, Status, Options);
   end Find_All_With_Captures;

   procedure Find_All_Lines
     (Expression : Regexp;
      Text       : String;
      Lines      : out Text_Range_Array;
      Count      : out Natural;
      Status     : out Find_All_Status;
      Options    : Match_Options := (others => <>))
   is
      Cursor : Match_Cursor;
      Found  : Match_Result;
   begin
      Lines := [others => (First => 0, Last => 0)];
      Count := 0;

      if not Expression.Valid then
         Status := Find_All_Invalid_Regexp;
         return;
      end if;

      Start (Cursor, Expression, Options => Options);
      loop
         Next (Cursor, Text, Found);
         case Found.Status is
            when Match_Ok =>
               if Count = Lines'Length then
                  Status := Too_Many_Matches;
                  return;
               end if;

               Lines (Lines'First + Count) := Match_Line_Range (Text, Found);
               Count := Count + 1;

            when No_Match =>
               Status := (if Count = 0 then No_Matches else Find_All_Ok);
               return;

            when Match_Limit_Exceeded =>
               Status := Find_All_Limit_Exceeded;
               return;

            when Invalid_Regexp =>
               Status := Find_All_Invalid_Regexp;
               return;
         end case;
      end loop;
   end Find_All_Lines;

   procedure Replace_All_Lines
     (Expression : Regexp;
      Text       : String;
      Lines      : out Text_Range_Array;
      Count      : out Natural;
      Status     : out Find_All_Status;
      Options    : Match_Options := (others => <>))
   is
   begin
      Find_All_Lines (Expression, Text, Lines, Count, Status, Options);
   end Replace_All_Lines;

   procedure Plan_Replacement
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Edits       : out Replacement_Edit_Array;
      Count       : out Natural;
      Status      : out Replace_Status;
      Complete    : out Boolean;
      Options     : Match_Options := (others => <>))
   is
      Found         : Match_Result;
      Captures      : Text_Range_Array (1 .. Max_Captures);
      Capture_Total : Natural;
      Next_From     : Positive := 1;
      Segment_First : Natural := 1;
      Detail        : Replacement_Validation_Result;
      Output_Next   : Natural := 1;

      function Local_Range_Length (First, Last : Natural) return Natural is
      begin
         if First = 0 or else Last < First then
            return 0;
         end if;

         return Last - First + 1;
      end Local_Range_Length;

      procedure Add_Edit (Source : Text_Range; Is_Replacement : Boolean; Required_Length : Natural) is
      begin
         if Source.First = 0 or else Source.Last < Source.First then
            return;
         elsif Count = Edits'Length then
            Complete := False;
            return;
         end if;

         Count := Count + 1;
         Edits (Edits'First + Count - 1) :=
           (Source           => Source,
            Is_Replacement   => Is_Replacement,
            Required_Length  => Required_Length,
            Output_First     => Output_Next,
            Output_Last      => (if Required_Length = 0 then Output_Next - 1 else Output_Next + Required_Length - 1),
            Reference_First  => 0,
            Reference_Last   => 0);
         Output_Next := Output_Next + Required_Length;
      end Add_Edit;
   begin
      Edits := [others => (others => <>)];
      Count := 0;
      Complete := True;

      if not Expression.Valid then
         Status := Replace_Invalid_Regexp;
         return;
      end if;

      Detail := Validate_Replacement_Detail (Expression, Replacement);
      if Detail.Status /= Replacement_Ok then
         Status := Replace_Invalid_Regexp;
         return;
      end if;

      loop
         Find_From_With_Captures (Expression, Text, Next_From, Found, Captures, Capture_Total, Options);
         case Found.Status is
            when Match_Ok =>
               Add_Edit
                 ((First => Segment_First, Last => Found.First - 1),
                  False,
                  Local_Range_Length (Segment_First, Found.First - 1));
               declare
                  Required : Natural := 0;
                  Sized    : Replace_Status;
                  Replaced : Natural;
               begin
                  if Found.Last >= Found.First then
                     Replace_First_Size
                       (Expression,
                        Text (Text'First + Found.First - 1 .. Text'First + Found.Last - 1),
                        Replacement,
                        Required,
                        Sized,
                        Replaced,
                        Options);
                     if Sized not in Replace_Ok | Replace_No_Match then
                        Status := Sized;
                        return;
                     end if;
                  else
                     Required := Replacement'Length;
                  end if;
                  Add_Edit ((First => Found.First, Last => Found.Last), True, Required);
               end;

               if Found.Last < Found.First then
                  Segment_First := Found.First;
                  exit when Found.First >= Text'Length + 1;
                  Next_From := Found.First + 1;
               else
                  Segment_First := Found.Last + 1;
                  exit when Found.Last >= Text'Length;
                  Next_From := Found.Last + 1;
               end if;

            when No_Match =>
               Add_Edit
                 ((First => Segment_First, Last => Text'Length),
                  False,
                  Local_Range_Length (Segment_First, Text'Length));
               Status :=
                 (if Count = 1 and then not Edits (Edits'First).Is_Replacement
                  then Replace_No_Match
                  else Replace_Ok);
               return;

            when Match_Limit_Exceeded =>
               Status := Replace_Limit_Exceeded;
               return;

            when Invalid_Regexp =>
               Status := Replace_Invalid_Regexp;
               return;
         end case;
      end loop;

      Add_Edit
        ((First => Segment_First, Last => Text'Length),
         False,
         Local_Range_Length (Segment_First, Text'Length));
      Status := Replace_Ok;
   end Plan_Replacement;

   procedure Plan_Replacement_Detail
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Edits       : out Replacement_Edit_Array;
      References  : out Replacement_Reference_Array;
      Maps        : out Replacement_Output_Map_Array;
      Plan        : out Replacement_Plan;
      Options     : Match_Options := (others => <>))
   is
      Detail       : Replacement_Validation_Result;
      Complete     : Boolean;
      Ref_Complete : Boolean;
   begin
      Plan := (others => <>);
      Maps := [others => (others => <>)];
      References := [others => (others => <>)];

      Plan_Replacement (Expression, Text, Replacement, Edits, Plan.Edit_Count, Plan.Status, Complete, Options);
      Plan.Complete := Complete;
      if Plan.Status not in Replace_Ok | Replace_No_Match then
         return;
      end if;

      Replacement_References
        (Expression, Replacement, References, Plan.Reference_Count, Detail, Ref_Complete);
      if Detail.Status /= Replacement_Ok then
         Plan.Status := Replace_Invalid_Regexp;
         Plan.Complete := False;
         return;
      end if;

      Plan.Complete := Plan.Complete and then Ref_Complete;
      for I in 1 .. Plan.Edit_Count loop
         Plan.Required_Length := Plan.Required_Length + Edits (Edits'First + I - 1).Required_Length;
         if I <= Maps'Length then
            Plan.Map_Count := Plan.Map_Count + 1;
            Maps (Maps'First + I - 1) :=
              (Source         => Edits (Edits'First + I - 1).Source,
               Output         =>
                 (First => Edits (Edits'First + I - 1).Output_First,
                  Last  => Edits (Edits'First + I - 1).Output_Last),
               Is_Replacement => Edits (Edits'First + I - 1).Is_Replacement);
            if Edits (Edits'First + I - 1).Is_Replacement and then Plan.Reference_Count /= 0 then
               Edits (Edits'First + I - 1).Reference_First := 1;
               Edits (Edits'First + I - 1).Reference_Last := Plan.Reference_Count;
            end if;
         else
            Plan.Complete := False;
         end if;
      end loop;
   end Plan_Replacement_Detail;

   function Find_All_Summary
     (Expression : Regexp;
      Text       : String;
      Options    : Match_Options := (others => <>))
      return Find_All_Summary_Result
   is
      Cursor : Match_Cursor;
      Found  : Match_Result;
      Result : Find_All_Summary_Result;
   begin
      if not Expression.Valid then
         Result.Status := Find_All_Invalid_Regexp;
         return Result;
      end if;

      Start (Cursor, Expression, Options => Options);
      loop
         Next (Cursor, Text, Found);
         if Found.Steps_Used > Natural'Last - Result.Steps_Used then
            Result.Status := Find_All_Limit_Exceeded;
            return Result;
         end if;
         Result.Steps_Used := Result.Steps_Used + Found.Steps_Used;

         case Found.Status is
            when Match_Ok =>
               if Result.Count = Natural'Last then
                  Result.Status := Too_Many_Matches;
                  return Result;
               end if;
               Result.Count := Result.Count + 1;
               if Result.Count = 1 then
                  Result.First_Match := Found;
               end if;
               Result.Last_Match := Found;

            when No_Match =>
               Result.Status := (if Result.Count = 0 then No_Matches else Find_All_Ok);
               return Result;

            when Match_Limit_Exceeded =>
               Result.Status := Find_All_Limit_Exceeded;
               return Result;

            when Invalid_Regexp =>
               Result.Status := Find_All_Invalid_Regexp;
               return Result;
         end case;
      end loop;
   end Find_All_Summary;

   function Find_All_Line_Summary
     (Expression : Regexp;
      Text       : String;
      Options    : Match_Options := (others => <>))
      return Find_All_Line_Summary_Result
   is
      Cursor : Match_Cursor;
      Found  : Match_Result;
      Result : Find_All_Line_Summary_Result;
   begin
      if not Expression.Valid then
         Result.Status := Find_All_Invalid_Regexp;
         return Result;
      end if;

      Start (Cursor, Expression, Options => Options);
      loop
         Next (Cursor, Text, Found);
         if Found.Steps_Used > Natural'Last - Result.Steps_Used then
            Result.Status := Find_All_Limit_Exceeded;
            return Result;
         end if;
         Result.Steps_Used := Result.Steps_Used + Found.Steps_Used;

         case Found.Status is
            when Match_Ok =>
               if Result.Count = Natural'Last then
                  Result.Status := Too_Many_Matches;
                  return Result;
               end if;
               Result.Count := Result.Count + 1;
               if Result.Count = 1 then
                  Result.First_Position := Line_Column (Text, Found.First);
                  Result.First_Line := Match_Line_Range (Text, Found);
               end if;
               Result.Last_Position := Line_Column (Text, Found.First);
               Result.Last_Line := Match_Line_Range (Text, Found);

            when No_Match =>
               Result.Status := (if Result.Count = 0 then No_Matches else Find_All_Ok);
               return Result;

            when Match_Limit_Exceeded =>
               Result.Status := Find_All_Limit_Exceeded;
               return Result;

            when Invalid_Regexp =>
               Result.Status := Find_All_Invalid_Regexp;
               return Result;
         end case;
      end loop;
   end Find_All_Line_Summary;

   procedure Find_All_Overlapping
     (Expression : Regexp;
      Text       : String;
      Matches    : out Match_Result_Array;
      Count      : out Natural;
      Status     : out Find_All_Status;
      Options    : Match_Options := (others => <>))
   is
   begin
      Find_All_Overlapping_From (Expression, Text, 1, Matches, Count, Status, Options);
   end Find_All_Overlapping;

   procedure Find_All_Overlapping_With_Captures
     (Expression    : Regexp;
      Text          : String;
      Matches       : out Match_Result_Array;
      Captures      : out Capture_Result_Array;
      Count         : out Natural;
      Capture_Count : out Natural;
      Status        : out Find_All_Status;
      Options       : Match_Options := (others => <>))
   is
   begin
      Find_All_Overlapping_With_Captures_From
        (Expression, Text, 1, Matches, Captures, Count, Capture_Count, Status, Options);
   end Find_All_Overlapping_With_Captures;

   procedure Find_All_With_Captures_From
     (Expression    : Regexp;
      Text          : String;
      From          : Positive;
      Matches       : out Match_Result_Array;
      Captures      : out Capture_Result_Array;
      Count         : out Natural;
      Capture_Count : out Natural;
      Status        : out Find_All_Status;
      Options       : Match_Options := (others => <>))
   is
      Found       : Match_Result;
      Local       : Text_Range_Array (1 .. Max_Captures);
      Local_Count : Natural;
      Next_From   : Positive := From;
      Total_Steps : Natural := 0;
      Remaining   : Natural;
      Run_Options : Match_Options := Options;
      Row         : Positive;
   begin
      Matches := [others => <>];
      Captures := [others => [others => Text_Range'(First => 0, Last => 0)]];
      Count := 0;
      Capture_Count := 0;

      if not Expression.Valid then
         Status := Find_All_Invalid_Regexp;
         return;
      end if;

      Capture_Count := Natural'Min (Expression.Capture_Count, Captures'Length (2));

      if From > Text'Length + 1 then
         Status := No_Matches;
         return;
      end if;

      loop
         pragma Loop_Invariant (Count <= Matches'Length);

         if Total_Steps >= Options.Max_Steps then
            Status := Find_All_Limit_Exceeded;
            return;
         end if;

         Remaining := Options.Max_Steps - Total_Steps;
         Run_Options.Max_Steps := Remaining;
         Find_From_With_Captures (Expression, Text, Next_From, Found, Local, Local_Count, Run_Options);

         if Found.Steps_Used > Natural'Last - Total_Steps then
            Status := Find_All_Limit_Exceeded;
            return;
         end if;
         Total_Steps := Total_Steps + Found.Steps_Used;

         case Found.Status is
            when Match_Ok =>
               if Count = Matches'Length or else Count = Captures'Length (1) then
                  Status := Too_Many_Matches;
                  return;
               end if;

               Found.Steps_Used := Total_Steps;
               Matches (Matches'First + Count) := Found;
               Row := Captures'First (1) + Count;
               for J in 1 .. Capture_Count loop
                  Captures (Row, Captures'First (2) + J - 1) := Local (J);
               end loop;
               Count := Count + 1;

               if Found.Last < Found.First then
                  if Found.First = Positive'Last then
                     Status := Find_All_Ok;
                     return;
                  end if;
                  Next_From := Found.First + 1;
               elsif Found.Last = Natural'Last then
                  Status := Find_All_Ok;
                  return;
               else
                  Next_From := Found.Last + 1;
               end if;

            when No_Match =>
               Status := (if Count = 0 then No_Matches else Find_All_Ok);
               return;

            when Match_Limit_Exceeded =>
               Status := Find_All_Limit_Exceeded;
               return;

            when Invalid_Regexp =>
               Status := Find_All_Invalid_Regexp;
               return;
         end case;
      end loop;
   end Find_All_With_Captures_From;

   procedure Find_All_From
     (Expression : Regexp;
      Text       : String;
      From       : Positive;
      Matches    : out Match_Result_Array;
      Count      : out Natural;
      Status     : out Find_All_Status;
      Options    : Match_Options := (others => <>))
   is
      Found       : Match_Result;
      Next_From   : Positive := From;
      Total_Steps : Natural := 0;
      Remaining   : Natural;
      Run_Options : Match_Options := Options;
   begin
      Matches := [others => <>];
      Count := 0;

      if not Expression.Valid then
         Status := Find_All_Invalid_Regexp;
         return;
      end if;

      if From > Text'Length + 1 then
         Status := No_Matches;
         return;
      end if;

      loop
         pragma Loop_Invariant (Count <= Matches'Length);

         if Total_Steps >= Options.Max_Steps then
            Status := Find_All_Limit_Exceeded;
            return;
         end if;

         Remaining := Options.Max_Steps - Total_Steps;
         Run_Options.Max_Steps := Remaining;
         Found := Find_From (Expression, Text, Next_From, Run_Options);

         if Found.Steps_Used > Natural'Last - Total_Steps then
            Status := Find_All_Limit_Exceeded;
            return;
         end if;
         Total_Steps := Total_Steps + Found.Steps_Used;

         case Found.Status is
            when Match_Ok =>
               if Count = Matches'Length then
                  Status := Too_Many_Matches;
                  return;
               end if;

               Matches (Matches'First + Count) := Found;
               Count := Count + 1;

               if Found.Last < Found.First then
                  if Found.First = Positive'Last then
                     Status := Find_All_Ok;
                     return;
                  end if;
                  Next_From := Found.First + 1;
               elsif Found.Last = Natural'Last then
                  Status := Find_All_Ok;
                  return;
               else
                  Next_From := Found.Last + 1;
               end if;

            when No_Match =>
               Status := (if Count = 0 then No_Matches else Find_All_Ok);
               return;

            when Match_Limit_Exceeded =>
               Status := Find_All_Limit_Exceeded;
               return;

            when Invalid_Regexp =>
               Status := Find_All_Invalid_Regexp;
               return;
         end case;
      end loop;
   end Find_All_From;

   procedure Find_All_Overlapping_With_Captures_From
     (Expression    : Regexp;
      Text          : String;
      From          : Positive;
      Matches       : out Match_Result_Array;
      Captures      : out Capture_Result_Array;
      Count         : out Natural;
      Capture_Count : out Natural;
      Status        : out Find_All_Status;
      Options       : Match_Options := (others => <>))
   is
      Found       : Match_Result;
      Local       : Text_Range_Array (1 .. Max_Captures);
      Local_Count : Natural;
      Next_From   : Positive := From;
      Total_Steps : Natural := 0;
      Remaining   : Natural;
      Run_Options : Match_Options := Options;
      Row         : Positive;
   begin
      Matches := [others => <>];
      Captures := [others => [others => Text_Range'(First => 0, Last => 0)]];
      Count := 0;
      Capture_Count := 0;

      if not Expression.Valid then
         Status := Find_All_Invalid_Regexp;
         return;
      end if;

      Capture_Count := Natural'Min (Expression.Capture_Count, Captures'Length (2));

      if From > Text'Length + 1 then
         Status := No_Matches;
         return;
      end if;

      loop
         pragma Loop_Invariant (Count <= Matches'Length);

         if Total_Steps >= Options.Max_Steps then
            Status := Find_All_Limit_Exceeded;
            return;
         end if;

         Remaining := Options.Max_Steps - Total_Steps;
         Run_Options.Max_Steps := Remaining;
         Find_From_With_Captures (Expression, Text, Next_From, Found, Local, Local_Count, Run_Options);

         if Found.Steps_Used > Natural'Last - Total_Steps then
            Status := Find_All_Limit_Exceeded;
            return;
         end if;
         Total_Steps := Total_Steps + Found.Steps_Used;

         case Found.Status is
            when Match_Ok =>
               if Count = Matches'Length or else Count = Captures'Length (1) then
                  Status := Too_Many_Matches;
                  return;
               end if;

               Found.Steps_Used := Total_Steps;
               Matches (Matches'First + Count) := Found;
               Row := Captures'First (1) + Count;
               for J in 1 .. Capture_Count loop
                  Captures (Row, Captures'First (2) + J - 1) := Local (J);
               end loop;
               Count := Count + 1;

               if Found.First = Positive'Last then
                  Status := Find_All_Ok;
                  return;
               end if;
               Next_From := Found.First + 1;

            when No_Match =>
               Status := (if Count = 0 then No_Matches else Find_All_Ok);
               return;

            when Match_Limit_Exceeded =>
               Status := Find_All_Limit_Exceeded;
               return;

            when Invalid_Regexp =>
               Status := Find_All_Invalid_Regexp;
               return;
         end case;
      end loop;
   end Find_All_Overlapping_With_Captures_From;

   procedure Find_All_Overlapping_From
     (Expression : Regexp;
      Text       : String;
      From       : Positive;
      Matches    : out Match_Result_Array;
      Count      : out Natural;
      Status     : out Find_All_Status;
      Options    : Match_Options := (others => <>))
   is
      Found       : Match_Result;
      Next_From   : Positive := From;
      Total_Steps : Natural := 0;
      Remaining   : Natural;
      Run_Options : Match_Options := Options;
   begin
      Matches := [others => <>];
      Count := 0;

      if not Expression.Valid then
         Status := Find_All_Invalid_Regexp;
         return;
      end if;

      if From > Text'Length + 1 then
         Status := No_Matches;
         return;
      end if;

      loop
         pragma Loop_Invariant (Count <= Matches'Length);

         if Total_Steps >= Options.Max_Steps then
            Status := Find_All_Limit_Exceeded;
            return;
         end if;

         Remaining := Options.Max_Steps - Total_Steps;
         Run_Options.Max_Steps := Remaining;
         Found := Find_From (Expression, Text, Next_From, Run_Options);

         if Found.Steps_Used > Natural'Last - Total_Steps then
            Status := Find_All_Limit_Exceeded;
            return;
         end if;
         Total_Steps := Total_Steps + Found.Steps_Used;

         case Found.Status is
            when Match_Ok =>
               if Count = Matches'Length then
                  Status := Too_Many_Matches;
                  return;
               end if;

               Matches (Matches'First + Count) := Found;
               Count := Count + 1;

               if Found.First = Positive'Last then
                  Status := Find_All_Ok;
                  return;
               end if;
               Next_From := Found.First + 1;

            when No_Match =>
               Status := (if Count = 0 then No_Matches else Find_All_Ok);
               return;

            when Match_Limit_Exceeded =>
               Status := Find_All_Limit_Exceeded;
               return;

            when Invalid_Regexp =>
               Status := Find_All_Invalid_Regexp;
               return;
         end case;
      end loop;
   end Find_All_Overlapping_From;

   procedure Count_Matches
     (Expression : Regexp;
      Text       : String;
      Count      : out Natural;
      Status     : out Find_All_Status;
      Options    : Match_Options := (others => <>))
   is
      Cursor : Match_Cursor;
      Found  : Match_Result;
   begin
      Count := 0;
      if not Expression.Valid then
         Status := Find_All_Invalid_Regexp;
         return;
      end if;

      Start (Cursor, Expression, Options => Options);
      loop
         Next (Cursor, Text, Found);
         case Found.Status is
            when Match_Ok =>
               if Count = Natural'Last then
                  Status := Too_Many_Matches;
                  return;
               end if;
               Count := Count + 1;

            when No_Match =>
               Status := (if Count = 0 then No_Matches else Find_All_Ok);
               return;

            when Match_Limit_Exceeded =>
               Status := Find_All_Limit_Exceeded;
               return;

            when Invalid_Regexp =>
               Status := Find_All_Invalid_Regexp;
               return;
         end case;
      end loop;
   end Count_Matches;

   function Find_First_Of
     (Expressions : Regexp_Array;
      Text        : String;
      Options     : Match_Options := (others => <>))
      return Pattern_Match_Result
   is
   begin
      return Find_From_Of (Expressions, Text, 1, Options);
   end Find_First_Of;

   function Find_From_Of
     (Expressions : Regexp_Array;
      Text        : String;
      From        : Positive;
      Options     : Match_Options := (others => <>))
      return Pattern_Match_Result
   is
      Best : Pattern_Match_Result := (others => <>);
   begin
      for I in Expressions'Range loop
         declare
            Found : constant Match_Result := Find_From_Planned (Expressions (I), Text, From, Options);
         begin
            case Found.Status is
               when Match_Ok =>
                  if Best.Found.Status /= Match_Ok
                    or else Found.First < Best.Found.First
                    or else (Found.First = Best.Found.First and then I < Expressions'First + Best.Pattern_Index - 1)
                  then
                     Best :=
                       (Pattern_Index => I - Expressions'First + 1,
                        Kind          => I - Expressions'First + 1,
                        Found         => Found);
                  end if;

               when Match_Limit_Exceeded =>
                  if Best.Found.Status /= Match_Ok then
                     return
                       (Pattern_Index => I - Expressions'First + 1,
                        Kind          => I - Expressions'First + 1,
                        Found         => Found);
                  end if;

               when Invalid_Regexp =>
                  if Best.Found.Status /= Match_Ok then
                     return
                       (Pattern_Index => I - Expressions'First + 1,
                        Kind          => I - Expressions'First + 1,
                        Found         => Found);
                  end if;

               when No_Match =>
                  null;
            end case;
         end;
      end loop;

      if Best.Found.Status = Match_Ok then
         return Best;
      end if;

      return (Pattern_Index => 0, Kind => 0, Found => (Status => No_Match, others => <>));
   end Find_From_Of;

   function Kind_For (Kinds : Natural_Array; Index : Natural) return Natural is
   begin
      if Index >= 1 and then Index <= Kinds'Length then
         return Kinds (Kinds'First + Index - 1);
      end if;

      return Index;
   end Kind_For;

   function Find_First_Of_With_Captures
     (Expressions : Regexp_Array;
      Text        : String;
      Options     : Match_Options := (others => <>))
      return Pattern_Match_Captures_Result
   is
   begin
      return Find_From_Of_With_Captures (Expressions, Text, 1, Options);
   end Find_First_Of_With_Captures;

   function Find_From_Of_With_Captures
     (Expressions : Regexp_Array;
      Text        : String;
      From        : Positive;
      Options     : Match_Options := (others => <>))
      return Pattern_Match_Captures_Result
   is
      Best : Pattern_Match_Captures_Result := (others => <>);
      Found : Match_Result;
      Captures : Capture_Buffer;
      Count : Natural;
   begin
      for I in Expressions'Range loop
         Find_From_Planned_With_Captures (Expressions (I), Text, From, Found, Captures, Count, Options);
         case Found.Status is
            when Match_Ok =>
               if Best.Match.Found.Status /= Match_Ok
                 or else Found.First < Best.Match.Found.First
                 or else (Found.First = Best.Match.Found.First and then I < Expressions'First + Best.Pattern_Index - 1)
               then
                  Best.Pattern_Index := I - Expressions'First + 1;
                  Best.Kind := Best.Pattern_Index;
                  Best.Match := (Found => Found, Captures => Captures, Capture_Count => Count);
               end if;

            when Match_Limit_Exceeded | Invalid_Regexp =>
               if Best.Match.Found.Status /= Match_Ok then
                  return
                    (Pattern_Index => I - Expressions'First + 1,
                     Kind          => I - Expressions'First + 1,
                     Match         => (Found => Found, Captures => Captures, Capture_Count => Count));
               end if;

            when No_Match =>
               null;
         end case;
      end loop;

      if Best.Match.Found.Status = Match_Ok then
         return Best;
      end if;

      return (Pattern_Index => 0, Kind => 0, Match => (others => <>));
   end Find_From_Of_With_Captures;

   procedure Tokenize
     (Expressions : Regexp_Array;
      Text        : String;
      Tokens      : out Pattern_Match_Array;
      Count       : out Natural;
      Status      : out Find_All_Status;
      Options     : Match_Options := (others => <>))
   is
      From  : Positive := 1;
      Token : Pattern_Match_Result;
   begin
      Tokens := [others => (others => <>)];
      Count := 0;

      loop
         Token := Find_From_Of (Expressions, Text, From, Options);
         case Token.Found.Status is
            when Match_Ok =>
               if Count = Tokens'Length then
                  Status := Too_Many_Matches;
                  return;
               end if;

               Count := Count + 1;
               Tokens (Tokens'First + Count - 1) := Token;

               if Token.Found.Last < Token.Found.First then
                  exit when Token.Found.First >= Text'Length + 1;
                  From := Token.Found.First + 1;
               else
                  exit when Token.Found.Last >= Text'Length;
                  From := Token.Found.Last + 1;
               end if;

            when No_Match =>
               Status := (if Count = 0 then No_Matches else Find_All_Ok);
               return;

            when Match_Limit_Exceeded =>
               Status := Find_All_Limit_Exceeded;
               return;

            when Invalid_Regexp =>
               Status := Find_All_Invalid_Regexp;
               return;
         end case;
      end loop;

      Status := (if Count = 0 then No_Matches else Find_All_Ok);
   end Tokenize;

   procedure Tokenize_With_Kinds
     (Expressions : Regexp_Array;
      Kinds       : Natural_Array;
      Text        : String;
      Tokens      : out Pattern_Match_Array;
      Count       : out Natural;
      Status      : out Find_All_Status;
      Options     : Match_Options := (others => <>))
   is
   begin
      Tokenize (Expressions, Text, Tokens, Count, Status, Options);
      for I in 1 .. Count loop
         Tokens (Tokens'First + I - 1).Kind := Kind_For (Kinds, Tokens (Tokens'First + I - 1).Pattern_Index);
      end loop;
   end Tokenize_With_Kinds;

   procedure Tokenize_With_Captures
     (Expressions : Regexp_Array;
      Kinds       : Natural_Array;
      Text        : String;
      Tokens      : out Pattern_Match_Captures_Array;
      Count       : out Natural;
      Status      : out Find_All_Status;
      Options     : Match_Options := (others => <>))
   is
      From  : Positive := 1;
      Token : Pattern_Match_Captures_Result;
   begin
      Tokens := [others => (others => <>)];
      Count := 0;

      loop
         Token := Find_From_Of_With_Captures (Expressions, Text, From, Options);
         case Token.Match.Found.Status is
            when Match_Ok =>
               if Count = Tokens'Length then
                  Status := Too_Many_Matches;
                  return;
               end if;

               Token.Kind := Kind_For (Kinds, Token.Pattern_Index);
               Count := Count + 1;
               Tokens (Tokens'First + Count - 1) := Token;

               if Token.Match.Found.Last < Token.Match.Found.First then
                  exit when Token.Match.Found.First >= Text'Length + 1;
                  From := Token.Match.Found.First + 1;
               else
                  exit when Token.Match.Found.Last >= Text'Length;
                  From := Token.Match.Found.Last + 1;
               end if;

            when No_Match =>
               Status := (if Count = 0 then No_Matches else Find_All_Ok);
               return;

            when Match_Limit_Exceeded =>
               Status := Find_All_Limit_Exceeded;
               return;

            when Invalid_Regexp =>
               Status := Find_All_Invalid_Regexp;
               return;
         end case;
      end loop;

      Status := (if Count = 0 then No_Matches else Find_All_Ok);
   end Tokenize_With_Captures;

   procedure Start
     (Cursor     : out Match_Cursor;
      Expression : Regexp;
      From       : Positive := 1;
      Options    : Match_Options := (others => <>))
   is
   begin
      Cursor :=
        (Expression => Expression,
         From       => From,
         Options    => Options,
         Done       => not Expression.Valid);
   end Start;

   procedure Next
     (Cursor : in out Match_Cursor;
      Text   : String;
      Found  : out Match_Result)
   is
   begin
      if Cursor.Done then
         Found := (Status => No_Match, others => <>);
         return;
      end if;

      Found := Find_From (Cursor.Expression, Text, Cursor.From, Cursor.Options);
      case Found.Status is
         when Match_Ok =>
            if Found.Last < Found.First then
               if Found.First = Positive'Last then
                  Cursor.Done := True;
               else
                  Cursor.From := Found.First + 1;
               end if;
            elsif Found.Last = Natural'Last then
               Cursor.Done := True;
            else
               Cursor.From := Found.Last + 1;
            end if;

         when others =>
            Cursor.Done := True;
      end case;
   end Next;

   procedure Next_With_Captures
     (Cursor   : in out Match_Cursor;
      Text     : String;
      Found    : out Match_Result;
      Captures : out Text_Range_Array;
      Count    : out Natural)
   is
   begin
      Count := 0;
      Captures := [others => (First => 0, Last => 0)];

      if Cursor.Done then
         Found := (Status => No_Match, others => <>);
         return;
      end if;

      Find_From_With_Captures (Cursor.Expression, Text, Cursor.From, Found, Captures, Count, Cursor.Options);
      case Found.Status is
         when Match_Ok =>
            if Found.Last < Found.First then
               if Found.First = Positive'Last then
                  Cursor.Done := True;
               else
                  Cursor.From := Found.First + 1;
               end if;
            elsif Found.Last = Natural'Last then
               Cursor.Done := True;
            else
               Cursor.From := Found.Last + 1;
            end if;

         when others =>
            Cursor.Done := True;
      end case;
   end Next_With_Captures;

   procedure Next_Captured
     (Cursor : in out Match_Cursor;
      Text   : String;
      Result : out Captured_Match_Result)
   is
   begin
      Result := (others => <>);
      Next_With_Captures (Cursor, Text, Result.Found, Result.Captures, Result.Capture_Count);
   end Next_Captured;

   procedure Next_Line_Captured
     (Cursor : in out Match_Cursor;
      Text   : String;
      Result : out Line_Captured_Match_Result)
   is
   begin
      Result := (others => <>);
      Next_Captured (Cursor, Text, Result.Match);
      if Result.Match.Found.Status = Match_Ok then
         Result.Position := Line_Column (Text, Result.Match.Found.First);
         Result.Line := Match_Line_Range (Text, Result.Match.Found);
      end if;
   end Next_Line_Captured;

   procedure Start_Token_Stream
     (Cursor : out Token_Stream_Cursor;
      Options : Match_Options := (others => <>))
   is
   begin
      Cursor :=
        (Buffer      => [others => Character'Val (0)],
         Length      => 0,
         Base_Offset => 1,
         Options     => Options,
         Final       => False);
   end Start_Token_Stream;

   procedure Feed_Tokens
     (Cursor      : in out Token_Stream_Cursor;
      Expressions : Regexp_Array;
      Kinds       : Natural_Array;
      Chunk       : String;
      Is_Final    : Boolean;
      Tokens      : out Pattern_Match_Array;
      Count       : out Natural;
      Status      : out Find_All_Status)
   is
      Local  : Pattern_Match_Array (Tokens'Range);
      L_Count : Natural;
      Last_Consumed : Natural := 0;
   begin
      Tokens := [others => (others => <>)];
      Count := 0;

      if Chunk'Length > Cursor.Buffer'Length - Cursor.Length then
         Status := Too_Many_Matches;
         return;
      end if;

      for I in Chunk'Range loop
         Cursor.Buffer (Cursor.Length + 1) := Chunk (I);
         Cursor.Length := Cursor.Length + 1;
      end loop;
      Cursor.Final := Is_Final;

      if Cursor.Length = 0 then
         Status := No_Matches;
         return;
      end if;

      Tokenize_With_Kinds
        (Expressions,
         Kinds,
         String (Cursor.Buffer (1 .. Cursor.Length)),
         Local,
         L_Count,
         Status,
         Cursor.Options);

      if Status = Find_All_Ok or else Status = No_Matches then
         for I in 1 .. L_Count loop
            exit when Count = Tokens'Length;
            Count := Count + 1;
            Tokens (Tokens'First + Count - 1) := Local (Local'First + I - 1);
            Tokens (Tokens'First + Count - 1).Found.First :=
              Local (Local'First + I - 1).Found.First + Cursor.Base_Offset - 1;
            Tokens (Tokens'First + Count - 1).Found.Last :=
              Local (Local'First + I - 1).Found.Last + Cursor.Base_Offset - 1;
            Last_Consumed := Local (Local'First + I - 1).Found.Last;
         end loop;

         if Count /= 0 and then Last_Consumed < Cursor.Length then
            declare
               Remaining : constant Natural := Cursor.Length - Last_Consumed;
            begin
               for I in 1 .. Remaining loop
                  Cursor.Buffer (I) := Cursor.Buffer (Last_Consumed + I);
               end loop;
               Cursor.Length := Remaining;
               Cursor.Base_Offset := Cursor.Base_Offset + Last_Consumed;
            end;
         elsif Count /= 0 then
            Cursor.Base_Offset := Cursor.Base_Offset + Cursor.Length;
            Cursor.Length := 0;
         end if;
      end if;
   end Feed_Tokens;

   procedure Feed_Tokens_Detail
     (Cursor      : in out Token_Stream_Cursor;
      Expressions : Regexp_Array;
      Kinds       : Natural_Array;
      Chunk       : String;
      Is_Final    : Boolean;
      Tokens      : out Pattern_Match_Array;
      Count       : out Natural;
      Status      : out Token_Stream_Status)
   is
      F_Status : Find_All_Status;
   begin
      Feed_Tokens (Cursor, Expressions, Kinds, Chunk, Is_Final, Tokens, Count, F_Status);
      case F_Status is
         when Find_All_Ok =>
            Status := Token_Stream_Ok;
         when No_Matches =>
            Status := (if Is_Final then Token_Stream_No_Token else Token_Stream_Need_More_Data);
         when Too_Many_Matches =>
            Status := Token_Stream_Output_Too_Small;
         when Find_All_Limit_Exceeded =>
            Status := Token_Stream_Limit_Exceeded;
         when Find_All_Invalid_Regexp =>
            Status := Token_Stream_Invalid_Regexp;
      end case;
   end Feed_Tokens_Detail;

   procedure Feed_Tokens_With_Captures
     (Cursor      : in out Token_Stream_Cursor;
      Expressions : Regexp_Array;
      Kinds       : Natural_Array;
      Chunk       : String;
      Is_Final    : Boolean;
      Tokens      : out Pattern_Match_Captures_Array;
      Count       : out Natural;
      Status      : out Token_Stream_Status)
   is
      Local  : Pattern_Match_Captures_Array (Tokens'Range);
      L_Count : Natural;
      F_Status : Find_All_Status;
      Last_Consumed : Natural := 0;
   begin
      Tokens := [others => (others => <>)];
      Count := 0;

      if Chunk'Length > Cursor.Buffer'Length - Cursor.Length then
         Status := Token_Stream_Buffer_Full;
         return;
      end if;

      for I in Chunk'Range loop
         Cursor.Buffer (Cursor.Length + 1) := Chunk (I);
         Cursor.Length := Cursor.Length + 1;
      end loop;
      Cursor.Final := Is_Final;

      if Cursor.Length = 0 then
         Status := (if Is_Final then Token_Stream_No_Token else Token_Stream_Need_More_Data);
         return;
      end if;

      Tokenize_With_Captures
        (Expressions,
         Kinds,
         String (Cursor.Buffer (1 .. Cursor.Length)),
         Local,
         L_Count,
         F_Status,
         Cursor.Options);

      case F_Status is
         when Find_All_Ok | No_Matches =>
            for I in 1 .. L_Count loop
               exit when Count = Tokens'Length;
               Count := Count + 1;
               Tokens (Tokens'First + Count - 1) := Local (Local'First + I - 1);
               Tokens (Tokens'First + Count - 1).Match.Found.First :=
                 Local (Local'First + I - 1).Match.Found.First + Cursor.Base_Offset - 1;
               Tokens (Tokens'First + Count - 1).Match.Found.Last :=
                 Local (Local'First + I - 1).Match.Found.Last + Cursor.Base_Offset - 1;
               for C in 1 .. Tokens (Tokens'First + Count - 1).Match.Capture_Count loop
                  Tokens (Tokens'First + Count - 1).Match.Captures (C).First :=
                    Local (Local'First + I - 1).Match.Captures (C).First + Cursor.Base_Offset - 1;
                  Tokens (Tokens'First + Count - 1).Match.Captures (C).Last :=
                    Local (Local'First + I - 1).Match.Captures (C).Last + Cursor.Base_Offset - 1;
               end loop;
               Last_Consumed := Local (Local'First + I - 1).Match.Found.Last;
            end loop;

            if Count /= 0 and then Last_Consumed < Cursor.Length then
               declare
                  Remaining : constant Natural := Cursor.Length - Last_Consumed;
               begin
                  for I in 1 .. Remaining loop
                     Cursor.Buffer (I) := Cursor.Buffer (Last_Consumed + I);
                  end loop;
                  Cursor.Length := Remaining;
                  Cursor.Base_Offset := Cursor.Base_Offset + Last_Consumed;
               end;
            elsif Count /= 0 then
               Cursor.Base_Offset := Cursor.Base_Offset + Cursor.Length;
               Cursor.Length := 0;
            end if;

            Status :=
              (if Count /= 0
               then Token_Stream_Ok
               elsif Is_Final
               then Token_Stream_No_Token
               else Token_Stream_Need_More_Data);

         when Too_Many_Matches =>
            Status := Token_Stream_Output_Too_Small;
         when Find_All_Limit_Exceeded =>
            Status := Token_Stream_Limit_Exceeded;
         when Find_All_Invalid_Regexp =>
            Status := Token_Stream_Invalid_Regexp;
      end case;
   end Feed_Tokens_With_Captures;

   procedure Start_Stream
     (Cursor     : out Stream_Cursor;
      Expression : Regexp;
      Options    : Match_Options := (others => <>))
   is
   begin
      Cursor :=
        (Expression  => Expression,
         Options     => Options,
         Buffer      => [others => Character'Val (0)],
         Length      => 0,
         Active_Buffer_Length => Default_Stream_Buffer_Length,
         Base_Offset => 1,
         Search_From => 1,
         Done        => not Expression.Valid,
         Final       => False);
   end Start_Stream;

   procedure Start_Stream
     (Cursor            : out Stream_Cursor;
      Expression        : Regexp;
      Max_Buffer_Length : Positive;
      Options           : Match_Options := (others => <>))
   is
   begin
      Cursor :=
        (Expression           => Expression,
         Options              => Options,
         Buffer               => [others => Character'Val (0)],
         Length               => 0,
         Active_Buffer_Length => Max_Buffer_Length,
         Base_Offset          => 1,
         Search_From          => 1,
         Done                 => not Expression.Valid,
         Final                => False);
   end Start_Stream;

   procedure Compact_Stream_Buffer (Cursor : in out Stream_Cursor) is
      Drop : Natural;
   begin
      if Cursor.Search_From = 1 then
         return;
      end if;

      Drop := Cursor.Search_From - 1;
      if Drop >= Cursor.Length then
         Cursor.Base_Offset := Cursor.Base_Offset + Cursor.Length;
         Cursor.Length := 0;
         Cursor.Search_From := 1;
         return;
      end if;

      for I in 1 .. Cursor.Length - Drop loop
         Cursor.Buffer (I) := Cursor.Buffer (I + Drop);
      end loop;
      Cursor.Base_Offset := Cursor.Base_Offset + Drop;
      Cursor.Length := Cursor.Length - Drop;
      Cursor.Search_From := 1;
   end Compact_Stream_Buffer;

   procedure Feed
     (Cursor   : in out Stream_Cursor;
      Chunk    : String;
      Is_Final : Boolean;
      Found    : out Match_Result;
      Status   : out Stream_Status)
   is
      Local      : Match_Result;
      Target     : Natural;
      At_Edge    : Boolean;
      First_Abs  : Natural;
      Last_Abs   : Natural;
      Run_Options : Match_Options := Cursor.Options;
   begin
      Found := (Status => No_Match, others => <>);

      if not Cursor.Expression.Valid then
         Status := Stream_Invalid_Regexp;
         Found.Status := Invalid_Regexp;
         Cursor.Done := True;
         return;
      elsif Cursor.Done then
         Status := Stream_No_Match;
         return;
      end if;

      Compact_Stream_Buffer (Cursor);
      if Chunk'Length > Cursor.Active_Buffer_Length - Cursor.Length then
         Status := Stream_Buffer_Full;
         return;
      end if;

      for I in Chunk'Range loop
         Cursor.Length := Cursor.Length + 1;
         Cursor.Buffer (Cursor.Length) := Chunk (I);
      end loop;
      Cursor.Final := Cursor.Final or else Is_Final;

      if Cursor.Length = 0 then
         Status := Stream_No_Match;
         if Cursor.Final then
            Cursor.Done := True;
         end if;
         return;
      end if;

      Run_Options.Max_Steps := Cursor.Options.Max_Steps;
      declare
         Length : constant Natural := Cursor.Length;
         Text   : String (1 .. Length);
      begin
         for I in 1 .. Length loop
            Text (I) := Cursor.Buffer (I);
         end loop;

         Local := Find_From (Cursor.Expression, Text, Cursor.Search_From, Run_Options);
      end;
      case Local.Status is
         when Match_Ok =>
            At_Edge :=
              (Local.Last >= Cursor.Length)
              or else (Local.Last < Local.First and then Local.First > Cursor.Length);
            if At_Edge and then not Cursor.Final and then not Cursor.Expression.Prefer_First_Match then
               Status := Stream_No_Match;
               return;
            end if;

            First_Abs := Cursor.Base_Offset + Local.First - 1;
            Last_Abs := Cursor.Base_Offset + Local.Last - 1;
            Found :=
              (Status     => Match_Ok,
               First      => First_Abs,
               Last       => Last_Abs,
               Steps_Used => Local.Steps_Used);
            Status := Stream_Match;

            if Local.Last < Local.First then
               if Local.First = Positive'Last then
                  Cursor.Done := True;
               else
                  Cursor.Search_From := Local.First + 1;
               end if;
            elsif Local.Last = Natural'Last then
               Cursor.Done := True;
            else
               Target := Local.Last + 1;
               Cursor.Search_From := Positive (Target);
            end if;

         when No_Match =>
            Status := Stream_No_Match;
            if Cursor.Final then
               Cursor.Done := True;
            end if;

         when Match_Limit_Exceeded =>
            Status := Stream_Limit_Exceeded;
            Found := Local;

         when Invalid_Regexp =>
            Status := Stream_Invalid_Regexp;
            Found := Local;
            Cursor.Done := True;
      end case;
   end Feed;

   procedure Feed_With_Captures
     (Cursor   : in out Stream_Cursor;
      Chunk    : String;
      Is_Final : Boolean;
      Found    : out Match_Result;
      Captures : out Text_Range_Array;
      Count    : out Natural;
      Status   : out Stream_Status)
   is
      Local       : Match_Result;
      Local_Caps  : Text_Range_Array (1 .. Max_Captures);
      Local_Count : Natural;
      Target      : Natural;
      At_Edge     : Boolean;
      First_Abs   : Natural;
      Last_Abs    : Natural;
      Run_Options : Match_Options := Cursor.Options;
   begin
      Found := (Status => No_Match, others => <>);
      Captures := [others => (First => 0, Last => 0)];
      Count := 0;

      if not Cursor.Expression.Valid then
         Status := Stream_Invalid_Regexp;
         Found.Status := Invalid_Regexp;
         Cursor.Done := True;
         return;
      elsif Cursor.Done then
         Status := Stream_No_Match;
         return;
      end if;

      Compact_Stream_Buffer (Cursor);
      if Chunk'Length > Cursor.Active_Buffer_Length - Cursor.Length then
         Status := Stream_Buffer_Full;
         return;
      end if;

      for I in Chunk'Range loop
         Cursor.Length := Cursor.Length + 1;
         Cursor.Buffer (Cursor.Length) := Chunk (I);
      end loop;
      Cursor.Final := Cursor.Final or else Is_Final;

      if Cursor.Length = 0 then
         Status := Stream_No_Match;
         if Cursor.Final then
            Cursor.Done := True;
         end if;
         return;
      end if;

      Run_Options.Max_Steps := Cursor.Options.Max_Steps;
      declare
         Length : constant Natural := Cursor.Length;
         Text   : String (1 .. Length);
      begin
         for I in 1 .. Length loop
            Text (I) := Cursor.Buffer (I);
         end loop;

         Find_From_With_Captures
           (Cursor.Expression, Text, Cursor.Search_From, Local, Local_Caps, Local_Count, Run_Options);
      end;

      case Local.Status is
         when Match_Ok =>
            At_Edge :=
              (Local.Last >= Cursor.Length)
              or else (Local.Last < Local.First and then Local.First > Cursor.Length);
            if At_Edge and then not Cursor.Final and then not Cursor.Expression.Prefer_First_Match then
               Status := Stream_No_Match;
               return;
            end if;

            First_Abs := Cursor.Base_Offset + Local.First - 1;
            Last_Abs := Cursor.Base_Offset + Local.Last - 1;
            Found :=
              (Status     => Match_Ok,
               First      => First_Abs,
               Last       => Last_Abs,
               Steps_Used => Local.Steps_Used);
            Status := Stream_Match;
            Count := Natural'Min (Local_Count, Captures'Length);
            for I in 1 .. Count loop
               if Local_Caps (I).First /= 0 then
                  Captures (Captures'First + I - 1) :=
                    (First => Cursor.Base_Offset + Local_Caps (I).First - 1,
                     Last  => Cursor.Base_Offset + Local_Caps (I).Last - 1);
               end if;
            end loop;

            if Local.Last < Local.First then
               if Local.First = Positive'Last then
                  Cursor.Done := True;
               else
                  Cursor.Search_From := Local.First + 1;
               end if;
            elsif Local.Last = Natural'Last then
               Cursor.Done := True;
            else
               Target := Local.Last + 1;
               Cursor.Search_From := Positive (Target);
            end if;

         when No_Match =>
            Status := Stream_No_Match;
            if Cursor.Final then
               Cursor.Done := True;
            end if;

         when Match_Limit_Exceeded =>
            Status := Stream_Limit_Exceeded;
            Found := Local;

         when Invalid_Regexp =>
            Status := Stream_Invalid_Regexp;
            Found := Local;
            Cursor.Done := True;
      end case;
   end Feed_With_Captures;

   procedure Append_String
     (Output : in out String;
      Last   : in out Natural;
      Value  : String;
      Ok     : out Boolean)
   is
      Target : Natural;
   begin
      Ok := True;
      if Value'Length > Output'Length - Last then
         Ok := False;
         return;
      end if;

      for I in Value'Range loop
         Target := Nat (Output'First) + Last;
         Output (Positive (Target)) := Value (I);
         Last := Last + 1;
      end loop;
   end Append_String;

   procedure Required_Prefix
     (Expression : Regexp;
      Output     : out String;
      Last       : out Natural;
      Status     : out Copy_Status)
   is
      Current : State_Index;
      Visited : array (Positive range 1 .. Default_Max_States) of Boolean := [others => False];
      Ok      : Boolean;
   begin
      Output := [others => Character'Val (0)];
      Last := 0;

      if not Expression.Valid or else Expression.Start = No_State then
         Status := Copy_No_Match;
         return;
      end if;

      Current := Expression.Start;
      while Current /= No_State and then not Visited (Positive (Current)) loop
         Visited (Positive (Current)) := True;
         declare
            Node : constant State := Expression.States (Positive (Current));
         begin
            case Node.Kind is
               when Node_Char =>
                  Append_String (Output, Last, String'(1 => Node.Ch), Ok);
                  if not Ok then
                     Status := Copy_Output_Too_Small;
                     return;
                  end if;
                  Current := Node.Out_1;

               when Node_Start_Line
                  | Node_End_Line
                  | Node_Word_Boundary
                  | Node_Not_Word_Boundary
                  | Node_Lookahead_Positive
                  | Node_Lookahead_Negative
                  | Node_Lookbehind_Positive
                  | Node_Lookbehind_Negative
                  | Node_Capture_Start
                  | Node_Capture_End =>
                  Current := Node.Out_1;

               when others =>
                  exit;
            end case;
         end;
      end loop;

      Status := Copy_Ok;
   end Required_Prefix;

   procedure Append_Fragment
     (Fragment : String;
      Pattern  : in out String;
      Last     : in out Natural;
      Status   : out Copy_Status)
   is
      Ok : Boolean;
   begin
      if Last > Pattern'Length then
         Status := Copy_Output_Too_Small;
         return;
      end if;

      Append_String (Pattern, Last, Fragment, Ok);
      Status := (if Ok then Copy_Ok else Copy_Output_Too_Small);
   end Append_Fragment;

   procedure Append_Literal
     (Literal : String;
      Pattern : in out String;
      Last    : in out Natural;
      Status  : out Copy_Status)
   is
      Ok : Boolean;
   begin
      if Last > Pattern'Length then
         Status := Copy_Output_Too_Small;
         return;
      end if;

      declare
         Escaped : constant String := Escape_Literal (Literal);
      begin
         Append_String (Pattern, Last, Escaped, Ok);
         Status := (if Ok then Copy_Ok else Copy_Output_Too_Small);
      end;
   end Append_Literal;

   procedure Append_Literal_Alternative
     (Literal : String;
      Pattern : in out String;
      Last    : in out Natural;
      Status  : out Copy_Status)
   is
      Ok : Boolean;
   begin
      if Last > Pattern'Length then
         Status := Copy_Output_Too_Small;
         return;
      end if;

      if Last /= 0 then
         Append_String (Pattern, Last, "|", Ok);
         if not Ok then
            Status := Copy_Output_Too_Small;
            return;
         end if;
      end if;

      Append_Literal (Literal, Pattern, Last, Status);
   end Append_Literal_Alternative;

   procedure Append_Class_Literal
     (Literal : Character;
      Pattern : in out String;
      Last    : in out Natural;
      Status  : out Copy_Status)
   is
   begin
      if Literal in '\' | ']' | '^' | '-' then
         Append_Fragment ("\" & String'(1 => Literal), Pattern, Last, Status);
      else
         Append_Fragment (String'(1 => Literal), Pattern, Last, Status);
      end if;
   end Append_Class_Literal;

   procedure Append_Class_Range
     (First  : Character;
      Last_Ch : Character;
      Pattern : in out String;
      Last    : in out Natural;
      Status  : out Copy_Status)
   is
   begin
      if Character'Pos (First) > Character'Pos (Last_Ch) then
         Status := Copy_No_Match;
         return;
      end if;

      Append_Class_Literal (First, Pattern, Last, Status);
      if Status /= Copy_Ok then
         return;
      end if;
      Append_Fragment ("-", Pattern, Last, Status);
      if Status /= Copy_Ok then
         return;
      end if;
      Append_Class_Literal (Last_Ch, Pattern, Last, Status);
   end Append_Class_Range;

   procedure Build_Literal_Alternation
     (Text     : String;
      Literals : Text_Range_Array;
      Pattern  : out String;
      Last     : out Natural;
      Status   : out Copy_Status)
   is
      First_Literal : Boolean := True;

      function Source_Index (Offset : Natural) return Positive is
        (Positive (Nat (Text'First) + Offset - 1));
   begin
      Pattern := [others => Character'Val (0)];
      Last := 0;
      Status := Copy_Ok;

      for I in Literals'Range loop
         declare
            Span : constant Text_Range := Literals (I);
         begin
            if Span.First = 0
              or else Span.First > Text'Length + 1
              or else (Span.Last >= Span.First and then Span.Last > Text'Length)
            then
               Status := Copy_No_Match;
               return;
            end if;

            if First_Literal then
               First_Literal := False;
            else
               Append_Fragment ("|", Pattern, Last, Status);
               if Status /= Copy_Ok then
                  return;
               end if;
            end if;

            if Span.Last >= Span.First then
               Append_Literal (Text (Source_Index (Span.First) .. Source_Index (Span.Last)), Pattern, Last, Status);
               if Status /= Copy_Ok then
                  return;
               end if;
            end if;
         end;
      end loop;
   end Build_Literal_Alternation;

   procedure Build_Literal_Word_Alternation
     (Text     : String;
      Literals : Text_Range_Array;
      Pattern  : out String;
      Last     : out Natural;
      Status   : out Copy_Status)
   is
      First_Literal : Boolean := True;

      function Source_Index (Offset : Natural) return Positive is
        (Positive (Nat (Text'First) + Offset - 1));
   begin
      Pattern := [others => Character'Val (0)];
      Last := 0;

      Append_Fragment ("\b(?:", Pattern, Last, Status);
      if Status /= Copy_Ok then
         return;
      end if;

      for I in Literals'Range loop
         declare
            Span : constant Text_Range := Literals (I);
         begin
            if Span.First = 0
              or else Span.Last < Span.First
              or else Span.Last > Text'Length
              or else not Is_Word (Text (Source_Index (Span.First)))
              or else not Is_Word (Text (Source_Index (Span.Last)))
            then
               Status := Copy_No_Match;
               return;
            end if;

            if First_Literal then
               First_Literal := False;
            else
               Append_Fragment ("|", Pattern, Last, Status);
               if Status /= Copy_Ok then
                  return;
               end if;
            end if;

            Append_Literal (Text (Source_Index (Span.First) .. Source_Index (Span.Last)), Pattern, Last, Status);
            if Status /= Copy_Ok then
               return;
            end if;
         end;
      end loop;

      Append_Fragment (")\b", Pattern, Last, Status);
   end Build_Literal_Word_Alternation;

   function Node_Image (Kind : Node_Kind) return String is
   begin
      case Kind is
         when Node_Invalid => return "invalid";
         when Node_Match => return "match";
         when Node_Char => return "char";
         when Node_Any => return "any";
         when Node_Class => return "class";
         when Node_Split => return "split";
         when Node_Start_Line => return "start_line";
         when Node_End_Line => return "end_line";
         when Node_Start_Absolute => return "start_absolute";
         when Node_End_Absolute => return "end_absolute";
         when Node_End_Absolute_Optional_Newline =>
            return "end_absolute_optional_newline";
         when Node_Word_Boundary => return "word_boundary";
         when Node_Not_Word_Boundary => return "not_word_boundary";
         when Node_Lookahead_Positive => return "lookahead_positive";
         when Node_Lookahead_Negative => return "lookahead_negative";
         when Node_Lookbehind_Positive => return "lookbehind_positive";
         when Node_Lookbehind_Negative => return "lookbehind_negative";
         when Node_Lookahead_Match => return "lookaround_match";
         when Node_Capture_Start => return "capture_start";
         when Node_Capture_End => return "capture_end";
         when Node_Backreference => return "backreference";
         when Node_Atomic => return "atomic";
      end case;
   end Node_Image;

   function Mode_Image (Mode : Option_Mode) return String is
   begin
      case Mode is
         when Option_Inherit => return "inherit";
         when Option_Off => return "off";
         when Option_On => return "on";
      end case;
   end Mode_Image;

   procedure Debug_Dump
     (Expression : Regexp;
      Output     : out String;
      Last       : out Natural;
      Status     : out Copy_Status)
   is
      Ok : Boolean;

      procedure Put (Text : String) is
      begin
         if Ok then
            Append_String (Output, Last, Text, Ok);
         end if;
      end Put;

      procedure Put_Line (Text : String) is
      begin
         Put (Text);
         Put (String'(1 => ASCII.LF));
      end Put_Line;
   begin
      Output := [others => Character'Val (0)];
      Last := 0;
      Status := Copy_Ok;
      Ok := True;

      if not Expression.Valid then
         Status := Copy_No_Match;
         return;
      end if;

      Put_Line ("regexp debug dump");
      Put_Line ("valid: true");
      Put_Line ("states:" & Natural'Image (Expression.State_Count));
      Put_Line ("start:" & Natural'Image (Natural (Expression.Start)));
      Put_Line ("captures:" & Natural'Image (Expression.Capture_Count));
      Put_Line ("prefer_first:" & (if Expression.Prefer_First_Match then " true" else " false"));
      Put_Line ("has_atomic:" & (if Expression.Has_Atomic then " true" else " false"));

      for I in 1 .. Expression.State_Count loop
         declare
            Node : constant State := Expression.States (I);
         begin
            Put
              ("state" & Natural'Image (I)
               & " kind=" & Node_Image (Node.Kind)
               & " out1=" & Natural'Image (Natural (Node.Out_1))
               & " out2=" & Natural'Image (Natural (Node.Out_2)));
            if Node.Kind = Node_Char then
               Put (" ch=");
               Put (String'(1 => Node.Ch));
            elsif Node.Kind in Node_Capture_Start | Node_Capture_End | Node_Backreference
              or else Node.Kind in Node_Lookbehind_Positive | Node_Lookbehind_Negative
            then
               Put (" capture=" & Natural'Image (Node.Capture));
            end if;
            Put
              (" case=" & Mode_Image (Node.Modes.Case_Sensitive)
               & " dot=" & Mode_Image (Node.Modes.Dot_Matches_Newline)
               & " multi=" & Mode_Image (Node.Modes.Multiline_Anchors));
            Put_Line ("");
         end;
      end loop;

      if not Ok then
         Status := Copy_Output_Too_Small;
      end if;
   end Debug_Dump;

   procedure Explain
     (Expression : Regexp;
      Output     : out String;
      Last       : out Natural;
      Status     : out Copy_Status)
   is
      Ok      : Boolean := True;
      F        : Pattern_Features;
      Prefix   : String (1 .. Default_Max_Pattern_Length);
      P_Last   : Natural;
      P_Status : Copy_Status;

      function Bool_Image (Value : Boolean) return String is
        (if Value then "true" else "false");

      procedure Put (Text : String) is
      begin
         if Ok then
            Append_String (Output, Last, Text, Ok);
         end if;
      end Put;

      procedure Put_Line (Text : String) is
      begin
         Put (Text);
         Put (String'(1 => ASCII.LF));
      end Put_Line;
   begin
      Output := [others => Character'Val (0)];
      Last := 0;

      if not Expression.Valid then
         Status := Copy_No_Match;
         return;
      end if;

      F := Features (Expression);
      Put_Line ("regexp explanation");
      Put_Line ("states:" & Natural'Image (Expression.State_Count));
      Put_Line ("captures:" & Natural'Image (Expression.Capture_Count));
      Put_Line ("has captures: " & Bool_Image (F.Has_Captures));
      Put_Line ("has named captures: " & Bool_Image (F.Has_Named_Captures));
      Put_Line ("has backreferences: " & Bool_Image (F.Has_Backreferences));
      Put_Line ("has anchors: " & Bool_Image (F.Has_Anchors));
      Put_Line ("has word boundaries: " & Bool_Image (F.Has_Word_Boundaries));
      Put_Line ("has lookaround: " & Bool_Image (F.Has_Lookaround));
      Put_Line ("has atomic: " & Bool_Image (F.Has_Atomic));
      Put_Line ("has classes: " & Bool_Image (F.Has_Character_Classes));
      Put_Line ("has dot: " & Bool_Image (F.Has_Dot));
      Put_Line ("has scoped options: " & Bool_Image (F.Has_Scoped_Options));
      Put_Line ("has splits: " & Bool_Image (F.Has_Splits));
      Put_Line ("may match empty: " & Bool_Image (F.May_Match_Empty));

      for I in 1 .. Natural'Min (Expression.Capture_Count, Max_Captures) loop
         if Expression.Capture_Name_Lengths (I) /= 0 then
            Put ("capture" & Natural'Image (I) & ": ");
            for J in 1 .. Expression.Capture_Name_Lengths (I) loop
               Put (String'(1 => Expression.Capture_Names (I) (J)));
            end loop;
            Put (String'(1 => ASCII.LF));
         end if;
      end loop;

      Required_Prefix (Expression, Prefix, P_Last, P_Status);
      if P_Status = Copy_Ok then
         Put ("required prefix: ");
         if P_Last /= 0 then
            Put (Prefix (1 .. P_Last));
         end if;
         Put (String'(1 => ASCII.LF));
      end if;

      Status := (if Ok then Copy_Ok else Copy_Output_Too_Small);
   end Explain;

   function Public_Node_Kind (Kind : Node_Kind) return Expression_Node_Kind is
   begin
      case Kind is
         when Node_Invalid =>
            return Expression_Node_Invalid;
         when Node_Match =>
            return Expression_Node_Match;
         when Node_Char =>
            return Expression_Node_Char;
         when Node_Any =>
            return Expression_Node_Any;
         when Node_Class =>
            return Expression_Node_Class;
         when Node_Split =>
            return Expression_Node_Split;
         when Node_Start_Line =>
            return Expression_Node_Start_Line;
         when Node_End_Line =>
            return Expression_Node_End_Line;
         when Node_Start_Absolute =>
            return Expression_Node_Start_Absolute;
         when Node_End_Absolute =>
            return Expression_Node_End_Absolute;
         when Node_End_Absolute_Optional_Newline =>
            return Expression_Node_End_Absolute_Optional_Newline;
         when Node_Word_Boundary =>
            return Expression_Node_Word_Boundary;
         when Node_Not_Word_Boundary =>
            return Expression_Node_Not_Word_Boundary;
         when Node_Lookahead_Positive
            | Node_Lookahead_Negative
            | Node_Lookbehind_Positive
            | Node_Lookbehind_Negative
            | Node_Lookahead_Match =>
            return Expression_Node_Lookaround;
         when Node_Capture_Start =>
            return Expression_Node_Capture_Start;
         when Node_Capture_End =>
            return Expression_Node_Capture_End;
         when Node_Backreference =>
            return Expression_Node_Backreference;
         when Node_Atomic =>
            return Expression_Node_Atomic;
      end case;
   end Public_Node_Kind;

   procedure Explain_Nodes
     (Expression : Regexp;
      Nodes      : out Expression_Node_Array;
      Count      : out Natural;
      Complete   : out Boolean)
   is
   begin
      Nodes := [others => (others => <>)];
      Count := 0;
      Complete := Expression.Valid and then Expression.State_Count <= Nodes'Length;

      if not Expression.Valid then
         return;
      end if;

      for I in 1 .. Expression.State_Count loop
         exit when Count = Nodes'Length;
         Count := Count + 1;
         Nodes (Nodes'First + Count - 1) :=
           (Kind    => Public_Node_Kind (Expression.States (I).Kind),
            Index   => I,
            Out_1   => Natural (Expression.States (I).Out_1),
            Out_2   => Natural (Expression.States (I).Out_2),
            Capture => Expression.States (I).Capture,
            Ch      => Expression.States (I).Ch,
            Zero_Width =>
              Expression.States (I).Kind in Node_Start_Line
                                           | Node_End_Line
                                           | Node_Word_Boundary
                                           | Node_Not_Word_Boundary
                                           | Node_Capture_Start
                                           | Node_Capture_End,
            Negated_Class =>
              Expression.States (I).Kind = Node_Class and then Expression.States (I).Class.Negated,
            Has_Scoped_Options => Expression.States (I).Modes /= (others => Option_Inherit));
      end loop;
   end Explain_Nodes;

   function Benchmark_Pattern (Case_Id : Benchmark_Case) return String is
   begin
      case Case_Id is
         when Benchmark_Identifier =>
            return Identifier_Pattern;
         when Benchmark_Integer =>
            return Integer_Pattern;
         when Benchmark_Email =>
            return Simple_Email_Pattern;
         when Benchmark_Url =>
            return Simple_URL_Pattern;
         when Benchmark_Key_Value =>
            return "(?<key>[A-Z_]\w*)=(?<value>\d+)";
         when Benchmark_Line_Comment =>
            return Line_Comment_Pattern;
      end case;
   end Benchmark_Pattern;

   function Benchmark_Text (Case_Id : Benchmark_Case) return String is
   begin
      case Case_Id is
         when Benchmark_Identifier =>
            return "alpha beta_2 Gamma";
         when Benchmark_Integer =>
            return "1 20 300 4000";
         when Benchmark_Email =>
            return "Ada <ada@example.org> Support <help@example.com>";
         when Benchmark_Url =>
            return "docs https://example.org/api and http://example.com";
         when Benchmark_Key_Value =>
            return "id=42 count=7";
         when Benchmark_Line_Comment =>
            return "code -- comment" & ASCII.LF & "next";
      end case;
   end Benchmark_Text;

   function Benchmark_Summary
     (Case_Id : Benchmark_Case;
      Options : Match_Options := (others => <>))
      return Find_All_Summary_Result
   is
      Compiled : constant Compile_Result := Compile (Benchmark_Pattern (Case_Id));
   begin
      if Compiled.Status /= Compile_Ok then
         return (Status => Find_All_Invalid_Regexp, others => <>);
      end if;

      return Find_All_Summary (Compiled.Expression, Benchmark_Text (Case_Id), Options);
   end Benchmark_Summary;

   procedure Copy_Token_Name
     (Names      : Token_Name_Array;
      Token_Kind : Natural;
      Output     : out String;
      Last       : out Natural;
      Status     : out Copy_Status)
   is
   begin
      Output := [others => Character'Val (0)];
      Last := 0;

      for I in Names'Range loop
         if Names (I).Kind = Token_Kind then
            if Names (I).Length > Output'Length then
               Status := Copy_Output_Too_Small;
               return;
            end if;

            for J in 1 .. Names (I).Length loop
               Output (Output'First + J - 1) := Names (I).Text (J);
            end loop;
            Last := Names (I).Length;
            Status := Copy_Ok;
            return;
         end if;
      end loop;

      Status := Copy_No_Match;
   end Copy_Token_Name;

   procedure Make_Token_Name
     (Token_Kind : Natural;
      Name       : String;
      Result     : out Token_Name;
      Status     : out Copy_Status)
   is
   begin
      Result := (others => <>);
      Result.Kind := Token_Kind;

      if Name'Length > Result.Text'Length then
         Status := Copy_Output_Too_Small;
         return;
      end if;

      for I in 1 .. Name'Length loop
         Result.Text (I) := Name (Name'First + I - 1);
      end loop;
      Result.Length := Name'Length;
      Status := Copy_Ok;
   end Make_Token_Name;

   procedure Format_Compile_Diagnostic
     (Pattern : String;
      Result  : Compile_Result;
      Output  : out String;
      Last    : out Natural;
      Status  : out Copy_Status)
   is
      Ok : Boolean := True;

      procedure Put (Text : String) is
      begin
         if Ok then
            Append_String (Output, Last, Text, Ok);
         end if;
      end Put;
   begin
      Output := [others => Character'Val (0)];
      Last := 0;
      Put (Diagnostic_Image (Result));
      Put (String'(1 => ASCII.LF));
      Put (Pattern);
      Put (String'(1 => ASCII.LF));

      if Result.Error_Offset /= 0 then
         for I in 1 .. Result.Error_Offset - 1 loop
            Put (" ");
         end loop;
         Put ("^");
         Put (String'(1 => ASCII.LF));
      end if;

      Status := (if Ok then Copy_Ok else Copy_Output_Too_Small);
   end Format_Compile_Diagnostic;

   procedure Format_Replacement_Diagnostic
     (Expression  : Regexp;
      Replacement : String;
      Output      : out String;
      Last        : out Natural;
      Status      : out Copy_Status)
   is
      Detail : constant Replacement_Validation_Result :=
        Validate_Replacement_Detail (Expression, Replacement);
      Ok     : Boolean := True;

      procedure Put (Text : String) is
      begin
         if Ok then
            Append_String (Output, Last, Text, Ok);
         end if;
      end Put;
   begin
      Output := [others => Character'Val (0)];
      Last := 0;
      Put (Status_Image (Detail.Status));
      if Detail.Error_Offset /= 0 then
         Put (" at offset" & Natural'Image (Detail.Error_Offset));
      end if;
      Put (String'(1 => ASCII.LF));
      Put (Replacement);
      Put (String'(1 => ASCII.LF));

      if Detail.Error_Offset /= 0 then
         for I in 1 .. Detail.Error_Offset - 1 loop
            Put (" ");
         end loop;
         Put ("^");
         Put (String'(1 => ASCII.LF));
      end if;

      Status := (if Ok then Copy_Ok else Copy_Output_Too_Small);
   end Format_Replacement_Diagnostic;

   type Replacement_Case is (Keep_Case, Upper_Case, Lower_Case, Title_Case);

   function Match_Case (Text : String; Found : Match_Result) return Replacement_Case is
      Start_Pos  : Natural;
      End_Pos    : Natural;
      Letters    : Natural := 0;
      Uppers     : Natural := 0;
      Lowers     : Natural := 0;
      First_Seen : Boolean := False;
      First_Upper : Boolean := False;
      Rest_Lower : Boolean := True;
   begin
      if Found.Last < Found.First then
         return Keep_Case;
      end if;

      Start_Pos := Nat (Text'First) + Found.First - 1;
      End_Pos := Nat (Text'First) + Found.Last - 1;
      for Pos in Start_Pos .. End_Pos loop
         if Is_Upper (Text (Positive (Pos))) or else Is_Lower (Text (Positive (Pos))) then
            Letters := Letters + 1;
            if Is_Upper (Text (Positive (Pos))) then
               Uppers := Uppers + 1;
            else
               Lowers := Lowers + 1;
            end if;

            if not First_Seen then
               First_Seen := True;
               First_Upper := Is_Upper (Text (Positive (Pos)));
            elsif Is_Upper (Text (Positive (Pos))) then
               Rest_Lower := False;
            end if;
         end if;
      end loop;

      if Letters = 0 then
         return Keep_Case;
      elsif Uppers = Letters then
         return Upper_Case;
      elsif Lowers = Letters then
         return Lower_Case;
      elsif First_Upper and then Rest_Lower then
         return Title_Case;
      else
         return Keep_Case;
      end if;
   end Match_Case;

   function Apply_Case (Ch : Character; Mode : Replacement_Case; First_Letter : Boolean) return Character is
   begin
      if not (Is_Upper (Ch) or else Is_Lower (Ch)) then
         return Ch;
      end if;

      case Mode is
         when Keep_Case =>
            return Ch;
         when Upper_Case =>
            return Upper (Ch);
         when Lower_Case =>
            return Fold (Ch);
         when Title_Case =>
            if First_Letter then
               return Upper (Ch);
            else
               return Fold (Ch);
            end if;
      end case;
   end Apply_Case;

   procedure Append_Text_Range
     (Text   : String;
      First  : Natural;
      Last_R : Natural;
      Output : in out String;
      Last   : in out Natural;
      Ok     : out Boolean);

   procedure Append_Text_Range_Replacement
     (Text          : String;
      First         : Natural;
      Last_R        : Natural;
      Base_Mode     : Replacement_Case;
      Forced_Mode   : Replacement_Case;
      Next_Mode     : in out Replacement_Case;
      First_Letter  : in out Boolean;
      Output        : in out String;
      Last          : in out Natural;
      Ok            : out Boolean);

   procedure Append_Replacement
     (Expression    : Regexp;
      Text          : String;
      Found         : Match_Result;
      Captures      : Text_Range_Array;
      Capture_Total : Natural;
      Replacement   : String;
      Preserve_Case : Boolean;
      Output        : in out String;
      Last          : in out Natural;
      Ok            : out Boolean)
   is
      Mode         : constant Replacement_Case :=
        (if Preserve_Case then Match_Case (Text, Found) else Keep_Case);
      Forced_Mode  : Replacement_Case := Keep_Case;
      Next_Mode    : Replacement_Case := Keep_Case;
      First_Letter : Boolean := True;
      Pos          : Natural := Nat (Replacement'First);
      Ch           : Character;
      Capture_No    : Natural;
      Name_First    : Natural;
      Name_Last     : Natural;
      Name_Index    : Natural;
   begin
      Ok := True;
      while Pos <= Nat (Replacement'Last) loop
         if Replacement (Positive (Pos)) = '\'
           and then Pos < Nat (Replacement'Last)
         then
            Pos := Pos + 1;
            if Replacement (Positive (Pos)) = '0' then
               Append_Text_Range_Replacement
                 (Text, Found.First, Found.Last, Mode, Forced_Mode, Next_Mode, First_Letter, Output, Last, Ok);
               if not Ok then
                  return;
               end if;
            elsif Replacement (Positive (Pos)) in '1' .. '9' then
               Capture_No := Character'Pos (Replacement (Positive (Pos))) - Character'Pos ('0');
               if Capture_No <= Capture_Total then
                  Append_Text_Range_Replacement
                    (Text,
                     Captures (Captures'First + Capture_No - 1).First,
                     Captures (Captures'First + Capture_No - 1).Last,
                     Mode,
                     Forced_Mode,
                     Next_Mode,
                     First_Letter,
                     Output,
                     Last,
                     Ok);
                  if not Ok then
                     return;
                  end if;
               else
                  Ch := Apply_Case (Replacement (Positive (Pos)), Mode, First_Letter);
                  Append_String (Output, Last, String'(1 => Ch), Ok);
                  if not Ok then
                     return;
                  end if;
               end if;
            elsif Replacement (Positive (Pos)) = 'k'
              and then Pos + 1 <= Nat (Replacement'Last)
              and then Replacement (Positive (Pos + 1)) = '<'
            then
               Name_First := Pos + 2;
               Name_Last := Name_First;
               while Name_Last <= Nat (Replacement'Last)
                 and then Replacement (Positive (Name_Last)) /= '>'
               loop
                  pragma Loop_Variant (Increases => Name_Last);
                  Advance (Name_Last);
               end loop;

               if Name_First <= Nat (Replacement'Last)
                 and then Name_Last <= Nat (Replacement'Last)
                 and then Name_Last > Name_First
               then
                  Name_Index :=
                    Capture_Index
                      (Expression, Replacement (Positive (Name_First) .. Positive (Name_Last - 1)));
                  if Name_Index /= 0 and then Name_Index <= Capture_Total then
                     Append_Text_Range_Replacement
                       (Text,
                        Captures (Captures'First + Name_Index - 1).First,
                        Captures (Captures'First + Name_Index - 1).Last,
                        Mode,
                        Forced_Mode,
                        Next_Mode,
                        First_Letter,
                        Output,
                        Last,
                        Ok);
                     if not Ok then
                        return;
                     end if;
                  end if;
                  Pos := Name_Last;
               else
                  Ch := Apply_Case ('k', (if Next_Mode /= Keep_Case then Next_Mode
                                          elsif Forced_Mode /= Keep_Case then Forced_Mode
                                          else Mode), First_Letter);
                  Next_Mode := Keep_Case;
                  Append_String (Output, Last, String'(1 => Ch), Ok);
                  if not Ok then
                     return;
                  end if;
               end if;
            elsif Replacement (Positive (Pos)) = 'U' then
               Forced_Mode := Upper_Case;
            elsif Replacement (Positive (Pos)) = 'L' then
               Forced_Mode := Lower_Case;
            elsif Replacement (Positive (Pos)) = 'E' then
               Forced_Mode := Keep_Case;
            elsif Replacement (Positive (Pos)) = 'u' then
               Next_Mode := Upper_Case;
            elsif Replacement (Positive (Pos)) = 'l' then
               Next_Mode := Lower_Case;
            elsif Replacement (Positive (Pos)) = '\' then
               Ch := Apply_Case ('\', (if Next_Mode /= Keep_Case then Next_Mode
                                       elsif Forced_Mode /= Keep_Case then Forced_Mode
                                       else Mode), First_Letter);
               Next_Mode := Keep_Case;
               Append_String (Output, Last, String'(1 => Ch), Ok);
               if not Ok then
                  return;
               end if;
            else
               Ch := Apply_Case (Replacement (Positive (Pos)),
                                 (if Next_Mode /= Keep_Case then Next_Mode
                                  elsif Forced_Mode /= Keep_Case then Forced_Mode
                                  else Mode),
                                 First_Letter);
               Next_Mode := Keep_Case;
               if Is_Upper (Replacement (Positive (Pos))) or else Is_Lower (Replacement (Positive (Pos))) then
                  First_Letter := False;
               end if;
               Append_String (Output, Last, String'(1 => Ch), Ok);
               if not Ok then
                  return;
               end if;
            end if;
         else
            Ch := Apply_Case (Replacement (Positive (Pos)),
                              (if Next_Mode /= Keep_Case then Next_Mode
                               elsif Forced_Mode /= Keep_Case then Forced_Mode
                               else Mode),
                              First_Letter);
            Next_Mode := Keep_Case;
            if Is_Upper (Replacement (Positive (Pos))) or else Is_Lower (Replacement (Positive (Pos))) then
               First_Letter := False;
            end if;
            Append_String (Output, Last, String'(1 => Ch), Ok);
            if not Ok then
               return;
            end if;
         end if;
         Pos := Pos + 1;
      end loop;
   end Append_Replacement;

   function Validate_Replacement_Detail
     (Expression  : Regexp;
      Replacement : String)
      return Replacement_Validation_Result
   is
      Pos        : Natural := Nat (Replacement'First);
      Escape_Pos : Natural;
      Capture_No : Natural;
      Name_First : Natural;
      Name_Last  : Natural;
      Name_Index : Natural;
      Span_Open  : Boolean := False;
      Result     : Replacement_Validation_Result;
   begin
      if not Expression.Valid then
         Result.Status := Replacement_Invalid_Regexp;
         return Result;
      end if;

      while Pos <= Nat (Replacement'Last) loop
         pragma Loop_Variant (Increases => Pos);
         if Replacement (Positive (Pos)) = '\' then
            Escape_Pos := Pos;
            if Pos = Nat (Replacement'Last) then
               Result.Status := Replacement_Invalid_Escape;
               Result.Error_Offset := Relative_Offset (Replacement'First, Escape_Pos);
               return Result;
            end if;

            Pos := Pos + 1;
            case Replacement (Positive (Pos)) is
               when '0' =>
                  null;

               when '1' .. '9' =>
                  Capture_No := Character'Pos (Replacement (Positive (Pos))) - Character'Pos ('0');
                  Result.Capture := Capture_No;
                  if Capture_No > Expression.Capture_Count then
                     Result.Status := Replacement_Unknown_Capture;
                     Result.Error_Offset := Relative_Offset (Replacement'First, Escape_Pos);
                     return Result;
                  end if;

               when 'k' =>
                  if Pos = Nat (Replacement'Last) or else Replacement (Positive (Pos + 1)) /= '<' then
                     Result.Status := Replacement_Invalid_Escape;
                     Result.Error_Offset := Relative_Offset (Replacement'First, Escape_Pos);
                     return Result;
                  end if;

                  Name_First := Pos + 2;
                  Name_Last := Name_First;
                  while Name_Last <= Nat (Replacement'Last)
                    and then Replacement (Positive (Name_Last)) /= '>'
                  loop
                     pragma Loop_Variant (Increases => Name_Last);
                     Name_Last := Name_Last + 1;
                  end loop;

                  if Name_Last > Nat (Replacement'Last) then
                     Result.Status := Replacement_Unterminated_Name;
                     Result.Error_Offset := Relative_Offset (Replacement'First, Escape_Pos);
                     Result.Name :=
                       (First => Relative_Offset (Replacement'First, Name_First),
                        Last  => Replacement'Length);
                     return Result;
                  elsif Name_Last = Name_First then
                     Result.Status := Replacement_Unknown_Capture;
                     Result.Error_Offset := Relative_Offset (Replacement'First, Escape_Pos);
                     Result.Name := (First => 0, Last => 0);
                     return Result;
                  else
                     Result.Name :=
                       (First => Relative_Offset (Replacement'First, Name_First),
                        Last  => Relative_Offset (Replacement'First, Name_Last - 1));
                     Name_Index :=
                       Capture_Index
                         (Expression, Replacement (Positive (Name_First) .. Positive (Name_Last - 1)));
                     Result.Capture := Name_Index;
                     if Name_Index = 0 then
                        Result.Status := Replacement_Unknown_Capture;
                        Result.Error_Offset := Relative_Offset (Replacement'First, Escape_Pos);
                        return Result;
                     end if;
                  end if;
                  Pos := Name_Last;

               when 'U' | 'L' =>
                  Span_Open := True;

               when 'E' =>
                  Span_Open := False;

               when 'u' | 'l' =>
                  if Pos = Nat (Replacement'Last) then
                     Result.Status := Replacement_Invalid_Escape;
                     Result.Error_Offset := Relative_Offset (Replacement'First, Escape_Pos);
                     return Result;
                  end if;

               when '\' =>
                  null;

               when others =>
                  Result.Status := Replacement_Invalid_Escape;
                  Result.Error_Offset := Relative_Offset (Replacement'First, Escape_Pos);
                  return Result;
            end case;
         end if;

         Pos := Pos + 1;
      end loop;

      if Span_Open then
         Result.Status := Replacement_Unterminated_Case_Conversion;
         Result.Error_Offset := Replacement'Length;
      end if;

      return Result;
   end Validate_Replacement_Detail;

   procedure Validate_Replacement
     (Expression    : Regexp;
      Replacement   : String;
      Status        : out Replacement_Validation_Status;
      Error_Offset  : out Natural)
   is
      Result : constant Replacement_Validation_Result :=
        Validate_Replacement_Detail (Expression, Replacement);
   begin
      Status := Result.Status;
      Error_Offset := Result.Error_Offset;
   end Validate_Replacement;

   procedure Replacement_References
     (Expression  : Regexp;
      Replacement : String;
      References  : out Replacement_Reference_Array;
      Count       : out Natural;
      Result      : out Replacement_Validation_Result;
      Complete    : out Boolean)
   is
      Pos        : Natural := Nat (Replacement'First);
      Escape_Pos : Natural;
      Capture_No : Natural;
      Name_First : Natural;
      Name_Last  : Natural;

      procedure Add (Ref : Replacement_Reference) is
      begin
         if Count < References'Length then
            References (References'First + Count) := Ref;
            Count := Count + 1;
         else
            Complete := False;
         end if;
      end Add;
   begin
      References := [others => (Kind => Replacement_Whole_Match, Offset => 0, Capture => 0, Name => (0, 0))];
      Count := 0;
      Complete := True;
      Result := Validate_Replacement_Detail (Expression, Replacement);
      if Result.Status /= Replacement_Ok then
         return;
      end if;

      while Pos <= Nat (Replacement'Last) loop
         if Replacement (Positive (Pos)) = '\'
           and then Pos < Nat (Replacement'Last)
         then
            Escape_Pos := Pos;
            Pos := Pos + 1;
            case Replacement (Positive (Pos)) is
               when '0' =>
                  Add
                    ((Kind    => Replacement_Whole_Match,
                      Offset  => Relative_Offset (Replacement'First, Escape_Pos),
                      Capture => 0,
                      Name    => (0, 0)));

               when '1' .. '9' =>
                  Capture_No := Character'Pos (Replacement (Positive (Pos))) - Character'Pos ('0');
                  Add
                    ((Kind    => Replacement_Numbered_Capture,
                      Offset  => Relative_Offset (Replacement'First, Escape_Pos),
                      Capture => Capture_No,
                      Name    => (0, 0)));

               when 'k' =>
                  if Pos < Nat (Replacement'Last)
                    and then Replacement (Positive (Pos + 1)) = '<'
                  then
                     Name_First := Pos + 2;
                     Name_Last := Name_First;
                     while Name_Last <= Nat (Replacement'Last)
                       and then Replacement (Positive (Name_Last)) /= '>'
                     loop
                        pragma Loop_Variant (Increases => Name_Last);
                        Name_Last := Name_Last + 1;
                     end loop;

                     if Name_Last <= Nat (Replacement'Last) and then Name_Last > Name_First then
                        Add
                          ((Kind    => Replacement_Named_Capture,
                            Offset  => Relative_Offset (Replacement'First, Escape_Pos),
                            Capture =>
                              Capture_Index
                                (Expression, Replacement (Positive (Name_First) .. Positive (Name_Last - 1))),
                            Name    =>
                              (First => Relative_Offset (Replacement'First, Name_First),
                               Last  => Relative_Offset (Replacement'First, Name_Last - 1))));
                        Pos := Name_Last;
                     end if;
                  end if;

               when others =>
                  null;
            end case;
         end if;

         Pos := Pos + 1;
      end loop;
   end Replacement_References;

   procedure Replacement_Summary
     (Expression  : Regexp;
      Replacement : String;
      References  : out Replacement_Reference_Array;
      Summary     : out Replacement_Features)
   is
      Count    : Natural;
      Complete : Boolean;
      Pos      : Natural := Nat (Replacement'First);
   begin
      Summary := (others => <>);
      Replacement_References (Expression, Replacement, References, Count, Summary.Validation, Complete);
      Summary.Valid := Summary.Validation.Status = Replacement_Ok;
      Summary.Reference_Count := Count;
      Summary.Complete := Complete;

      if not Summary.Valid then
         return;
      end if;

      for I in 1 .. Count loop
         case References (References'First + I - 1).Kind is
            when Replacement_Whole_Match =>
               Summary.Uses_Whole_Match := True;
            when Replacement_Numbered_Capture =>
               Summary.Uses_Numbered_Captures := True;
            when Replacement_Named_Capture =>
               Summary.Uses_Named_Captures := True;
         end case;
      end loop;

      while Pos <= Nat (Replacement'Last) loop
         if Replacement (Positive (Pos)) = '\'
           and then Pos < Nat (Replacement'Last)
         then
            Pos := Pos + 1;
            if Replacement (Positive (Pos)) in 'U' | 'L' | 'u' | 'l' then
               Summary.Uses_Case_Conversion := True;
            end if;
         end if;
         Pos := Pos + 1;
      end loop;
   end Replacement_Summary;

   function Escape_Replacement (Replacement : String) return String
      with SPARK_Mode => Off
   is
   begin
      if Replacement'Length = 0 then
         return "";
      end if;

      declare
         Escaped : String (1 .. Replacement'Length * 2) := [others => Character'Val (0)];
         Last    : Natural := 0;
      begin
         for Ch of Replacement loop
            if Ch = '\' then
               Last := Last + 1;
               Escaped (Last) := '\';
            end if;
            Last := Last + 1;
            Escaped (Last) := Ch;
         end loop;

         return Escaped (1 .. Last);
      end;
   end Escape_Replacement;

   procedure Append_Text_Range_Replacement
     (Text          : String;
      First         : Natural;
      Last_R        : Natural;
      Base_Mode     : Replacement_Case;
      Forced_Mode   : Replacement_Case;
      Next_Mode     : in out Replacement_Case;
      First_Letter  : in out Boolean;
      Output        : in out String;
      Last          : in out Natural;
      Ok            : out Boolean)
   is
      Start_Pos : Natural;
      End_Pos   : Natural;
      Mode      : Replacement_Case;
      Ch        : Character;
   begin
      Ok := True;
      if Last_R < First then
         return;
      end if;

      Start_Pos := Nat (Text'First) + First - 1;
      End_Pos := Nat (Text'First) + Last_R - 1;
      if Start_Pos < Nat (Text'First) or else End_Pos > Nat (Text'Last) then
         Ok := False;
         return;
      end if;

      for Pos in Start_Pos .. End_Pos loop
         Mode :=
           (if Next_Mode /= Keep_Case then Next_Mode
            elsif Forced_Mode /= Keep_Case then Forced_Mode
            else Base_Mode);
         Ch := Apply_Case (Text (Positive (Pos)), Mode, First_Letter);
         Next_Mode := Keep_Case;
         if Is_Upper (Text (Positive (Pos))) or else Is_Lower (Text (Positive (Pos))) then
            First_Letter := False;
         end if;
         Append_String (Output, Last, String'(1 => Ch), Ok);
         if not Ok then
            return;
         end if;
      end loop;
   end Append_Text_Range_Replacement;

   procedure Append_Text_Range
     (Text   : String;
      First  : Natural;
      Last_R : Natural;
      Output : in out String;
      Last   : in out Natural;
      Ok     : out Boolean)
   is
      Start_Pos : Natural;
      End_Pos   : Natural;
   begin
      Ok := True;
      if Last_R < First then
         return;
      end if;

      Start_Pos := Nat (Text'First) + First - 1;
      End_Pos := Nat (Text'First) + Last_R - 1;
      if Start_Pos < Nat (Text'First) or else End_Pos > Nat (Text'Last) then
         Ok := False;
         return;
      end if;

      Append_String (Output, Last, Text (Positive (Start_Pos) .. Positive (End_Pos)), Ok);
   end Append_Text_Range;

   procedure Copy_Range
     (Text   : String;
      Span   : Text_Range;
      Output : out String;
      Last   : out Natural;
      Status : out Copy_Status)
   is
      Ok : Boolean;
   begin
      Output := [others => Character'Val (0)];
      Last := 0;

      if Span.First = 0
        or else Span.First > Text'Length + 1
        or else (Span.Last >= Span.First and then Span.Last > Text'Length)
      then
         Status := Copy_No_Match;
         return;
      end if;

      Append_Text_Range (Text, Span.First, Span.Last, Output, Last, Ok);
      Status := (if Ok then Copy_Ok else Copy_Output_Too_Small);
   end Copy_Range;

   procedure Copy_Before
     (Text   : String;
      Found  : Match_Result;
      Output : out String;
      Last   : out Natural;
      Status : out Copy_Status)
   is
      Before : Text_Range;
      Match  : Text_Range;
      After  : Text_Range;
   begin
      Match_Context (Text, Found, Before, Match, After, Status);
      if Status = Copy_Ok then
         Copy_Range (Text, Before, Output, Last, Status);
      else
         Output := [others => Character'Val (0)];
         Last := 0;
      end if;
   end Copy_Before;

   procedure Copy_After
     (Text   : String;
      Found  : Match_Result;
      Output : out String;
      Last   : out Natural;
      Status : out Copy_Status)
   is
      Before : Text_Range;
      Match  : Text_Range;
      After  : Text_Range;
   begin
      Match_Context (Text, Found, Before, Match, After, Status);
      if Status = Copy_Ok then
         Copy_Range (Text, After, Output, Last, Status);
      else
         Output := [others => Character'Val (0)];
         Last := 0;
      end if;
   end Copy_After;

   procedure Copy_Match_Line
     (Text   : String;
      Found  : Match_Result;
      Output : out String;
      Last   : out Natural;
      Status : out Copy_Status)
   is
   begin
      Copy_Range (Text, Match_Line_Range (Text, Found), Output, Last, Status);
   end Copy_Match_Line;

   procedure Copy_Capture
     (Text     : String;
      Captures : Text_Range_Array;
      Index    : Positive;
      Output   : out String;
      Last     : out Natural;
      Status   : out Copy_Status)
   is
   begin
      if Index > Captures'Length then
         Output := [others => Character'Val (0)];
         Last := 0;
         Status := Copy_No_Match;
      else
         Copy_Range (Text, Captures (Captures'First + Index - 1), Output, Last, Status);
      end if;
   end Copy_Capture;

   procedure Copy_Named_Capture
     (Expression : Regexp;
      Text       : String;
      Captures   : Text_Range_Array;
      Name       : String;
      Output     : out String;
      Last       : out Natural;
      Status     : out Copy_Status)
   is
      Index : constant Natural := Capture_Index (Expression, Name);
   begin
      if Index = 0 then
         Output := [others => Character'Val (0)];
         Last := 0;
         Status := Copy_No_Match;
      else
         Copy_Capture (Text, Captures, Index, Output, Last, Status);
      end if;
   end Copy_Named_Capture;

   function Named_Capture_Range
     (Expression : Regexp;
      Captures   : Text_Range_Array;
      Name       : String)
      return Text_Range
   is
      Index : constant Natural := Capture_Index (Expression, Name);
   begin
      if Index = 0 or else Index > Captures'Length then
         return (First => 0, Last => 0);
      end if;

      return Captures (Captures'First + Index - 1);
   end Named_Capture_Range;

   function Range_Length (First, Last_R : Natural) return Natural is
   begin
      if Last_R < First then
         return 0;
      else
         return Last_R - First + 1;
      end if;
   end Range_Length;

   procedure Add_Length (Target : in out Natural; Amount : Natural; Ok : in out Boolean) is
   begin
      if Amount > Natural'Last - Target then
         Ok := False;
      else
         Target := Target + Amount;
      end if;
   end Add_Length;

   procedure Measure_Replacement
     (Expression    : Regexp;
      Text          : String;
      Found         : Match_Result;
      Captures      : Text_Range_Array;
      Capture_Total : Natural;
      Replacement   : String;
      Length        : in out Natural;
      Ok            : in out Boolean)
   is
      Pos        : Natural := Nat (Replacement'First);
      Capture_No : Natural;
      Name_First : Natural;
      Name_Last  : Natural;
      Name_Index : Natural;
   begin
      while Ok and then Pos <= Nat (Replacement'Last) loop
         if Replacement (Positive (Pos)) = '\'
           and then Pos < Nat (Replacement'Last)
         then
            Pos := Pos + 1;
            if Replacement (Positive (Pos)) = '0' then
               Add_Length (Length, Range_Length (Found.First, Found.Last), Ok);
            elsif Replacement (Positive (Pos)) in '1' .. '9' then
               Capture_No := Character'Pos (Replacement (Positive (Pos))) - Character'Pos ('0');
               if Capture_No <= Capture_Total then
                  Add_Length
                    (Length,
                     Range_Length
                       (Captures (Captures'First + Capture_No - 1).First,
                        Captures (Captures'First + Capture_No - 1).Last),
                     Ok);
               else
                  Add_Length (Length, 1, Ok);
               end if;
            elsif Replacement (Positive (Pos)) = 'k'
              and then Pos + 1 <= Nat (Replacement'Last)
              and then Replacement (Positive (Pos + 1)) = '<'
            then
               Name_First := Pos + 2;
               Name_Last := Name_First;
               while Name_Last <= Nat (Replacement'Last)
                 and then Replacement (Positive (Name_Last)) /= '>'
               loop
                  pragma Loop_Variant (Increases => Name_Last);
                  Advance (Name_Last);
               end loop;

               if Name_First <= Nat (Replacement'Last)
                 and then Name_Last <= Nat (Replacement'Last)
                 and then Name_Last > Name_First
               then
                  Name_Index :=
                    Capture_Index
                      (Expression, Replacement (Positive (Name_First) .. Positive (Name_Last - 1)));
                  if Name_Index /= 0 and then Name_Index <= Capture_Total then
                     Add_Length
                       (Length,
                        Range_Length
                          (Captures (Captures'First + Name_Index - 1).First,
                           Captures (Captures'First + Name_Index - 1).Last),
                        Ok);
                  end if;
                  Pos := Name_Last;
               else
                  Add_Length (Length, 1, Ok);
               end if;
            elsif Replacement (Positive (Pos)) in 'U' | 'L' | 'E' | 'u' | 'l' then
               null;
            else
               Add_Length (Length, 1, Ok);
            end if;
         else
            Add_Length (Length, 1, Ok);
         end if;

         Pos := Pos + 1;
      end loop;
   end Measure_Replacement;

   procedure Replace_Size_Impl
     (Expression      : Regexp;
      Text            : String;
      Replacement     : String;
      Required_Length : out Natural;
      Status          : out Replace_Status;
      Count           : out Natural;
      Options         : Match_Options;
      First_Only      : Boolean)
   is
      Found         : Match_Result;
      Captures      : Text_Range_Array (1 .. Max_Captures);
      Capture_Total : Natural := 0;
      Next_From     : Positive := 1;
      Segment_First : Natural := 1;
      Any_Match     : Boolean := False;
      Ok            : Boolean := True;
   begin
      Required_Length := 0;
      Count := 0;

      if not Expression.Valid then
         Status := Replace_Invalid_Regexp;
         return;
      end if;

      loop
         Find_From_With_Captures (Expression, Text, Next_From, Found, Captures, Capture_Total, Options);
         case Found.Status is
            when Match_Ok =>
               Any_Match := True;
               Count := Count + 1;
               Add_Length (Required_Length, Range_Length (Segment_First, Found.First - 1), Ok);
               Measure_Replacement
                 (Expression, Text, Found, Captures, Capture_Total, Replacement, Required_Length, Ok);
               if not Ok then
                  Status := Replace_Output_Too_Small;
                  return;
               end if;

               if Found.Last < Found.First then
                  Segment_First := Found.First;
                  if Found.First = Positive'Last then
                     exit;
                  end if;
                  Next_From := Found.First + 1;
               else
                  Segment_First := Found.Last + 1;
                  if Found.Last = Natural'Last then
                     exit;
                  end if;
                  Next_From := Found.Last + 1;
               end if;

               exit when First_Only;

            when No_Match =>
               exit;

            when Match_Limit_Exceeded =>
               Status := Replace_Limit_Exceeded;
               return;

            when Invalid_Regexp =>
               Status := Replace_Invalid_Regexp;
               return;
         end case;
      end loop;

      Add_Length (Required_Length, Range_Length (Segment_First, Text'Length), Ok);
      if not Ok then
         Status := Replace_Output_Too_Small;
      else
         Status := (if Any_Match then Replace_Ok else Replace_No_Match);
      end if;
   end Replace_Size_Impl;

   procedure Replace_Impl
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Output      : out String;
      Last        : out Natural;
      Status      : out Replace_Status;
      Count       : out Natural;
      Options     : Match_Options;
      First_Only  : Boolean;
      Preserve_Case : Boolean)
   is
      Found         : Match_Result;
      Captures      : Text_Range_Array (1 .. Max_Captures);
      Capture_Total : Natural := 0;
      Next_From     : Positive := 1;
      Segment_First : Natural := 1;
      Any_Match     : Boolean := False;
      Ok            : Boolean;
   begin
      Output := [others => Character'Val (0)];
      Last := 0;
      Count := 0;

      if not Expression.Valid then
         Status := Replace_Invalid_Regexp;
         return;
      end if;

      loop
         Find_From_With_Captures (Expression, Text, Next_From, Found, Captures, Capture_Total, Options);
         case Found.Status is
            when Match_Ok =>
               Any_Match := True;
               Count := Count + 1;
               Append_Text_Range (Text, Segment_First, Found.First - 1, Output, Last, Ok);
               if not Ok then
                  Status := Replace_Output_Too_Small;
                  return;
               end if;

               Append_Replacement
                 (Expression,
                  Text,
                  Found,
                  Captures,
                  Capture_Total,
                  Replacement,
                  Preserve_Case,
                  Output,
                  Last,
                  Ok);
               if not Ok then
                  Status := Replace_Output_Too_Small;
                  return;
               end if;

               if Found.Last < Found.First then
                  Segment_First := Found.First;
                  if Found.First = Positive'Last then
                     exit;
                  end if;
                  Next_From := Found.First + 1;
               else
                  Segment_First := Found.Last + 1;
                  if Found.Last = Natural'Last then
                     exit;
                  end if;
                  Next_From := Found.Last + 1;
               end if;

               exit when First_Only;

            when No_Match =>
               exit;

            when Match_Limit_Exceeded =>
               Status := Replace_Limit_Exceeded;
               return;

            when Invalid_Regexp =>
               Status := Replace_Invalid_Regexp;
               return;
         end case;
      end loop;

      Append_Text_Range (Text, Segment_First, Text'Length, Output, Last, Ok);
      if not Ok then
         Status := Replace_Output_Too_Small;
         return;
      end if;

      Status := (if Any_Match then Replace_Ok else Replace_No_Match);
   end Replace_Impl;

   procedure Replace_First
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Output      : out String;
      Last        : out Natural;
      Status      : out Replace_Status;
      Options     : Match_Options := (others => <>))
   is
      Count : Natural;
   begin
      Replace_Impl (Expression, Text, Replacement, Output, Last, Status, Count, Options, True, False);
   end Replace_First;

   procedure Replace_First_Count
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Output      : out String;
      Last        : out Natural;
      Status      : out Replace_Status;
      Count       : out Natural;
      Options     : Match_Options := (others => <>))
   is
   begin
      Replace_Impl (Expression, Text, Replacement, Output, Last, Status, Count, Options, True, False);
   end Replace_First_Count;

   procedure Replace_All
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Output      : out String;
      Last        : out Natural;
      Status      : out Replace_Status;
      Options     : Match_Options := (others => <>))
   is
      Count : Natural;
   begin
      Replace_Impl (Expression, Text, Replacement, Output, Last, Status, Count, Options, False, False);
   end Replace_All;

   procedure Replace_All_Count
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Output      : out String;
      Last        : out Natural;
      Status      : out Replace_Status;
      Count       : out Natural;
      Options     : Match_Options := (others => <>))
   is
   begin
      Replace_Impl (Expression, Text, Replacement, Output, Last, Status, Count, Options, False, False);
   end Replace_All_Count;

   procedure Replace_First_Size
     (Expression      : Regexp;
      Text            : String;
      Replacement     : String;
      Required_Length : out Natural;
      Status          : out Replace_Status;
      Count           : out Natural;
      Options         : Match_Options := (others => <>))
   is
   begin
      Replace_Size_Impl (Expression, Text, Replacement, Required_Length, Status, Count, Options, True);
   end Replace_First_Size;

   procedure Replace_All_Size
     (Expression      : Regexp;
      Text            : String;
      Replacement     : String;
      Required_Length : out Natural;
      Status          : out Replace_Status;
      Count           : out Natural;
      Options         : Match_Options := (others => <>))
   is
   begin
      Replace_Size_Impl (Expression, Text, Replacement, Required_Length, Status, Count, Options, False);
   end Replace_All_Size;

   procedure Required_First_Output_Length
     (Expression      : Regexp;
      Text            : String;
      Replacement     : String;
      Required_Length : out Natural;
      Status          : out Replace_Status;
      Options         : Match_Options := (others => <>))
   is
      Count : Natural;
   begin
      Replace_First_Size (Expression, Text, Replacement, Required_Length, Status, Count, Options);
   end Required_First_Output_Length;

   procedure Required_All_Output_Length
     (Expression      : Regexp;
      Text            : String;
      Replacement     : String;
      Required_Length : out Natural;
      Status          : out Replace_Status;
      Options         : Match_Options := (others => <>))
   is
      Count : Natural;
   begin
      Replace_All_Size (Expression, Text, Replacement, Required_Length, Status, Count, Options);
   end Required_All_Output_Length;

   procedure Replacement_Fits
     (Expression    : Regexp;
      Text          : String;
      Replacement   : String;
      Output_Length : Natural;
      Fits          : out Boolean;
      Status        : out Replace_Status;
      Options       : Match_Options := (others => <>))
   is
      Required : Natural;
   begin
      Required_All_Output_Length (Expression, Text, Replacement, Required, Status, Options);
      Fits := Status = Replace_Ok and then Required <= Output_Length;
   end Replacement_Fits;

   procedure Replace_First_Preserving_Case
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Output      : out String;
      Last        : out Natural;
      Status      : out Replace_Status;
      Options     : Match_Options := (others => <>))
   is
      Count : Natural;
   begin
      Replace_Impl (Expression, Text, Replacement, Output, Last, Status, Count, Options, True, True);
   end Replace_First_Preserving_Case;

   procedure Replace_All_Preserving_Case
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Output      : out String;
      Last        : out Natural;
      Status      : out Replace_Status;
      Options     : Match_Options := (others => <>))
   is
      Count : Natural;
   begin
      Replace_Impl (Expression, Text, Replacement, Output, Last, Status, Count, Options, False, True);
   end Replace_All_Preserving_Case;

   procedure Split
     (Expression : Regexp;
      Text       : String;
      Parts      : out Text_Range_Array;
      Count      : out Natural;
      Status     : out Split_Status;
      Options    : Match_Options := (others => <>))
   is
      Cursor        : Match_Cursor;
      Found         : Match_Result;
      Segment_First : Natural := 1;

      procedure Add_Part (First, Last_R : Natural) is
      begin
         if Count = Parts'Length then
            Status := Too_Many_Parts;
            return;
         end if;

         Parts (Parts'First + Count) := (First => First, Last => Last_R);
         Count := Count + 1;
      end Add_Part;
   begin
      Parts := [others => <>];
      Count := 0;
      Status := Split_Ok;

      if not Expression.Valid then
         Status := Split_Invalid_Regexp;
         return;
      end if;

      Start (Cursor, Expression, Options => Options);
      loop
         Next (Cursor, Text, Found);
         case Found.Status is
            when Match_Ok =>
               Add_Part (Segment_First, Found.First - 1);
               exit when Status /= Split_Ok;
               if Found.Last < Found.First then
                  Segment_First := Found.First;
               else
                  Segment_First := Found.Last + 1;
               end if;

            when No_Match =>
               exit;

            when Match_Limit_Exceeded =>
               Status := Split_Limit_Exceeded;
               return;

            when Invalid_Regexp =>
               Status := Split_Invalid_Regexp;
               return;
         end case;
      end loop;

      if Status = Split_Ok then
         Add_Part (Segment_First, Text'Length);
      end if;
   end Split;

   procedure Split_Lines
     (Expression : Regexp;
      Text       : String;
      Lines      : out Text_Range_Array;
      Count      : out Natural;
      Status     : out Split_Status;
      Options    : Match_Options := (others => <>))
   is
      Parts      : Text_Range_Array (1 .. Lines'Length);
      Part_Count : Natural;
      Found      : Match_Result;
   begin
      Lines := [others => (First => 0, Last => 0)];
      Count := 0;
      Split (Expression, Text, Parts, Part_Count, Status, Options);
      if Status /= Split_Ok then
         Count := Part_Count;
         return;
      end if;

      Count := Part_Count;
      for I in 1 .. Part_Count loop
         if Parts (Parts'First + I - 1).First /= 0
           and then Parts (Parts'First + I - 1).Last >= Parts (Parts'First + I - 1).First
         then
            Found :=
              (Status => Match_Ok,
               First  => Parts (Parts'First + I - 1).First,
               Last   => Parts (Parts'First + I - 1).Last,
               Steps_Used => 0);
            Lines (Lines'First + I - 1) := Match_Line_Range (Text, Found);
         end if;
      end loop;
   end Split_Lines;

   procedure Copy_Match
     (Text   : String;
      Found  : Match_Result;
      Output : out String;
      Last   : out Natural;
      Status : out Copy_Status)
   is
      Ok : Boolean;
   begin
      Output := [others => Character'Val (0)];
      Last := 0;

      if Found.Status /= Match_Ok or else Found.Last < Found.First then
         Status := Copy_No_Match;
         return;
      end if;

      Append_Text_Range (Text, Found.First, Found.Last, Output, Last, Ok);
      if Ok then
         Status := Copy_Ok;
      else
         Status := Copy_Output_Too_Small;
      end if;
   end Copy_Match;

   function Matches_Entire
     (Expression : Regexp;
      Text       : String;
      Options    : Match_Options := (others => <>))
      return Match_Result
   is
   begin
      if not Expression.Valid then
         return (Status => Invalid_Regexp, others => <>);
      end if;

      return Run_From (Expression, Text, Pos_Or_First (Text'First), True, Options);
   end Matches_Entire;

   function Lint (Expression : Regexp) return Pattern_Lint is
      F      : constant Pattern_Features := Features (Expression);
      Prefix : String (1 .. Default_Max_Pattern_Length);
      Last   : Natural;
      Status : Copy_Status;
      Result : Pattern_Lint;
   begin
      if not Expression.Valid then
         return Result;
      end if;

      Required_Prefix (Expression, Prefix, Last, Status);
      Result.Valid := True;
      Result.May_Match_Empty := F.May_Match_Empty;
      Result.Uses_Lookaround_In_Stream := F.Has_Lookaround;
      Result.No_Required_Prefix := Status /= Copy_Ok or else Last = 0;

      if Expression.Source_Length >= 2 then
         for I in 1 .. Expression.Source_Length - 1 loop
            if Expression.Source_Pattern (I) = '.'
              and then Expression.Source_Pattern (I + 1) in '*' | '+'
            then
               Result.Broad_Dot_Star := True;
            end if;
         end loop;
      end if;

      return Result;
   end Lint;

   function Is_Syntax_Error (Status : Compile_Status) return Boolean is
   begin
      return Status in Invalid_Capture_Name
        | Duplicate_Capture_Name
        | Invalid_Escape
        | Unterminated_Class
        | Empty_Class
        | Invalid_Class_Range
        | Invalid_Quantifier
        | Quantifier_Without_Atom
        | Unsupported_Syntax;
   end Is_Syntax_Error;

   function Is_Unsupported (Status : Compile_Status) return Boolean is
   begin
      return Status = Unsupported_Syntax;
   end Is_Unsupported;

   function Is_Limit_Error (Status : Compile_Status) return Boolean is
   begin
      return Status in Pattern_Too_Long | Too_Many_States | Too_Many_Captures;
   end Is_Limit_Error;

   function Is_Limit_Error (Status : Match_Status) return Boolean is
   begin
      return Status = Match_Limit_Exceeded;
   end Is_Limit_Error;

   function Is_Limit_Error (Status : Find_All_Status) return Boolean is
   begin
      return Status = Find_All_Limit_Exceeded;
   end Is_Limit_Error;

   function Is_Limit_Error (Status : Replace_Status) return Boolean is
   begin
      return Status = Replace_Limit_Exceeded;
   end Is_Limit_Error;

   function Is_Limit_Error (Status : Split_Status) return Boolean is
   begin
      return Status = Split_Limit_Exceeded;
   end Is_Limit_Error;

   function Is_Limit_Error (Status : Stream_Status) return Boolean is
   begin
      return Status in Stream_Limit_Exceeded | Stream_Buffer_Full;
   end Is_Limit_Error;

   function Status_Image (Status : Compile_Status) return String is
   begin
      case Status is
         when Compile_Ok => return "compile ok";
         when Empty_Pattern => return "empty pattern";
         when Pattern_Too_Long => return "pattern too long";
         when Too_Many_States => return "too many states";
         when Too_Many_Captures => return "too many captures";
         when Invalid_Capture_Name => return "invalid capture name";
         when Duplicate_Capture_Name => return "duplicate capture name";
         when Invalid_Escape => return "invalid escape";
         when Unterminated_Class => return "unterminated class";
         when Empty_Class => return "empty class";
         when Invalid_Class_Range => return "invalid class range";
         when Invalid_Quantifier => return "invalid quantifier";
         when Quantifier_Without_Atom => return "quantifier without atom";
         when Unsupported_Syntax => return "unsupported syntax";
      end case;
   end Status_Image;

   function Diagnostic_Image (Result : Compile_Result) return String is
   begin
      if Result.Error_Offset = 0 then
         return Status_Image (Result.Status);
      end if;

      return Status_Image (Result.Status) & " at offset" & Natural'Image (Result.Error_Offset);
   end Diagnostic_Image;

   function Status_Image (Status : Match_Status) return String is
   begin
      case Status is
         when Match_Ok => return "match ok";
         when No_Match => return "no match";
         when Match_Limit_Exceeded => return "match limit exceeded";
         when Invalid_Regexp => return "invalid regexp";
      end case;
   end Status_Image;

   function Status_Image (Status : Find_All_Status) return String is
   begin
      case Status is
         when Find_All_Ok => return "find all ok";
         when No_Matches => return "no matches";
         when Too_Many_Matches => return "too many matches";
         when Find_All_Limit_Exceeded => return "match limit exceeded";
         when Find_All_Invalid_Regexp => return "invalid regexp";
      end case;
   end Status_Image;

   function Status_Image (Status : Replace_Status) return String is
   begin
      case Status is
         when Replace_Ok => return "replace ok";
         when Replace_No_Match => return "no match";
         when Replace_Output_Too_Small => return "output too small";
         when Replace_Limit_Exceeded => return "match limit exceeded";
         when Replace_Invalid_Regexp => return "invalid regexp";
      end case;
   end Status_Image;

   function Status_Image (Status : Replacement_Validation_Status) return String is
   begin
      case Status is
         when Replacement_Ok => return "replacement ok";
         when Replacement_Invalid_Regexp => return "invalid regexp";
         when Replacement_Invalid_Escape => return "invalid replacement escape";
         when Replacement_Unknown_Capture => return "unknown replacement capture";
         when Replacement_Unterminated_Name => return "unterminated replacement name";
         when Replacement_Unterminated_Case_Conversion => return "unterminated replacement case conversion";
      end case;
   end Status_Image;

   function Status_Image (Status : Split_Status) return String is
   begin
      case Status is
         when Split_Ok => return "split ok";
         when Too_Many_Parts => return "too many parts";
         when Split_Limit_Exceeded => return "match limit exceeded";
         when Split_Invalid_Regexp => return "invalid regexp";
      end case;
   end Status_Image;

   function Status_Image (Status : Copy_Status) return String is
   begin
      case Status is
         when Copy_Ok => return "copy ok";
         when Copy_No_Match => return "no match";
         when Copy_Output_Too_Small => return "output too small";
      end case;
   end Status_Image;

   function Status_Image (Status : Stream_Status) return String is
   begin
      case Status is
         when Stream_Match => return "stream match";
         when Stream_No_Match => return "no match";
         when Stream_Limit_Exceeded => return "match limit exceeded";
         when Stream_Buffer_Full => return "stream buffer full";
         when Stream_Invalid_Regexp => return "invalid regexp";
      end case;
   end Status_Image;

   function Status_Image (Status : Pattern_Policy_Status) return String is
   begin
      case Status is
         when Policy_Ok => return "policy ok";
         when Policy_Invalid_Regexp => return "invalid regexp";
         when Policy_Disallowed_Feature => return "disallowed pattern feature";
         when Policy_Disallowed_Empty_Match => return "disallowed empty match";
      end case;
   end Status_Image;

end Regexp;
