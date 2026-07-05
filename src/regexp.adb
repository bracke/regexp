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

   function Equal_Chars (Left, Right : Character; Case_Sensitive : Boolean) return Boolean is
   begin
      if Case_Sensitive then
         return Left = Right;
      end if;

      return Fold (Left) = Fold (Right);
   end Equal_Chars;

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

   procedure Add_Range (Class : in out Character_Class; First, Last : Character) is
   begin
      for Pos in Character'Pos (First) .. Character'Pos (Last) loop
         Class.Members (Character'Val (Pos)) := True;
      end loop;
   end Add_Range;

   procedure Merge (Target : in out Character_Class; Source : Character_Class) is
   begin
      if Source.Negated then
         for Ch in Character loop
            Target.Members (Ch) := Target.Members (Ch) or else not Source.Members (Ch);
         end loop;
      else
         for Ch in Character loop
            Target.Members (Ch) := Target.Members (Ch) or else Source.Members (Ch);
         end loop;
      end if;
   end Merge;

   function Matches_Class
     (Class          : Character_Class;
      Ch             : Character;
      Case_Sensitive : Boolean)
      return Boolean
   is
      Hit : Boolean := Class.Members (Ch);
   begin
      if not Case_Sensitive then
         Hit := Hit or else Class.Members (Fold (Ch)) or else Class.Members (Upper (Ch));
      end if;

      if Class.Negated then
         return not Hit;
      end if;

      return Hit;
   end Matches_Class;

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
      Class      : Character_Class := (others => <>))
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
      Expression.States (Positive (Index)).Class := Class;
      Frag.Start := Index;
      Append_Out (Frag, (State => Index, Field => Patch_Out_1), Ok);
      if not Ok then
         Frag := (others => <>);
      end if;
   end Atom_Fragment;

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
      Ok := True;

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
         when '.' | '*' | '+' | '?' | '(' | ')' | '[' | ']' | '{' | '}' | '\' | '^' | '$' | '-' =>
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
      Good    : out Boolean)
      with Pre => Pos >= Nat (Pattern'First)
                  and then Pos <= Nat (Pattern'Last)
                  and then Pattern'Last < Positive'Last
   is
      procedure Read_Item
        (Item   : out Character_Class;
         Single : out Boolean;
         Ch     : out Character;
         Good   : out Boolean)
      with Pre  => Pos >= Nat (Pattern'First)
                   and then Pos <= Nat (Pattern'Last)
                   and then Pattern'Last < Positive'Last,
           Post => Pos >= Pos'Old
                   and then Pos <= Nat (Pattern'Last) + 1
                   and then (if Good then Pos > Pos'Old)
      is
      begin
         Item := (others => <>);
         Single := False;
         Ch := Character'Val (0);
         Good := False;

         if Pos < Positive'First or else Pos > Nat (Pattern'Last) then
            return;
         end if;

         if Pattern (Positive (Pos)) = '\' then
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
            Advance (Pos);
         else
            Ch := Pattern (Positive (Pos));
            Single := True;
            Item.Members (Ch) := True;
            Advance (Pos);
            Good := True;
         end if;
      end Read_Item;

      Item       : Character_Class;
      Range_End  : Character_Class;
      Single     : Boolean;
      End_Single : Boolean;
      Ch         : Character;
      End_Ch     : Character;
      Item_Good  : Boolean;
      Had_Item   : Boolean := False;
      Negated    : Boolean := False;
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
         pragma Loop_Invariant (Pos <= Nat (Pattern'Last));
         pragma Loop_Variant (Increases => Pos);

         Read_Item (Item, Single, Ch, Item_Good);
         if not Item_Good then
            return;
         end if;

         if Pos <= Nat (Pattern'Last)
           and then Pattern (Positive (Pos)) = '-'
           and then Pos < Nat (Pattern'Last)
           and then Pattern (Positive (Pos + 1)) /= ']'
         then
            if not Single then
               Status := Invalid_Class_Range;
               Offset := Pos;
               return;
            end if;

            Advance (Pos);
            Read_Item (Range_End, End_Single, End_Ch, Item_Good);
            if not Item_Good then
               return;
            end if;
            if Range_End.Negated or else not End_Single or else Character'Pos (Ch) > Character'Pos (End_Ch) then
               Status := Invalid_Class_Range;
               Offset := (if Pos = 0 then 0 else Pos - 1);
               return;
            end if;
            Add_Range (Class, Ch, End_Ch);
         else
            Merge (Class, Item);
         end if;

         Had_Item := True;
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
         when '.' | '*' | '+' | '?' | '(' | ')' | '[' | ']' | '{' | '}' | '\' | '^' | '$' =>
            Kind := Node_Char;
            Ch := Escaped;
         when others =>
            Good := False;
            return;
      end case;

   end Escape_Atom;

   function Compile
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
   is
      Result    : Compile_Result;
      Pos       : Natural := Nat (Pattern'First);
      Have_Frag : Boolean := False;
      Current   : Fragment;
      Atom      : Fragment;
      Kind      : Node_Kind;
      Ch        : Character;
      Class     : Character_Class;
      Status    : Compile_Status;
      Offset    : Natural;
      Ok        : Boolean;
      Match     : State_Index;
      Quantified : Fragment;
   begin
      Result.Expression := (others => <>);

      if Pattern'Length = 0 then
         Result.Status := Empty_Pattern;
         return Result;
      end if;

      if Pattern'Length > Max_Pattern_Length then
         Result.Status := Pattern_Too_Long;
         Result.Error_Offset := Max_Pattern_Length + 1;
         return Result;
      end if;

      while Pos <= Nat (Pattern'Last) loop
         pragma Loop_Invariant (Pos >= Nat (Pattern'First));
         pragma Loop_Invariant (Pos >= Positive'First);
         pragma Loop_Invariant (Pos <= Nat (Pattern'Last));
         pragma Loop_Variant (Increases => Pos);

         Ch := Character'Val (0);
         Class := (others => <>);

         case Pattern (Positive (Pos)) is
            when '*' | '+' | '?' =>
               Result.Status := Quantifier_Without_Atom;
               Result.Error_Offset := Relative_Offset (Pattern'First, Pos);
               return Result;

            when '(' | ')' | '|' | '{' | '}' =>
               Result.Status := Unsupported_Syntax;
               Result.Error_Offset := Relative_Offset (Pattern'First, Pos);
               return Result;

            when '.' =>
               Kind := Node_Any;
               Advance (Pos);

            when '^' =>
               Kind := Node_Start_Line;
               Advance (Pos);

            when '$' =>
               Kind := Node_End_Line;
               Advance (Pos);

            when '[' =>
               declare
                  Before_Class : constant Natural := Pos;
               begin
                  Parse_Class (Pattern, Pos, Class, Status, Offset, Ok);
                  if not Ok then
                     Result.Status := Status;
                     Result.Error_Offset := Relative_Offset (Pattern'First, Offset);
                     return Result;
                  elsif Pos <= Before_Class then
                     Result.Status := Invalid_Quantifier;
                     Result.Error_Offset := Relative_Offset (Pattern'First, Before_Class);
                     return Result;
                  end if;
               end;
               Kind := Node_Class;

            when '\' =>
               Advance (Pos);
               if Pos > Nat (Pattern'Last) then
                  Result.Status := Invalid_Escape;
                  Result.Error_Offset := Pattern'Length;
                  return Result;
               end if;
               Escape_Atom (Pattern (Positive (Pos)), Kind, Ch, Class, Ok);
               if not Ok then
                  Result.Status := Invalid_Escape;
                  Result.Error_Offset := Relative_Offset (Pattern'First, Pos);
                  return Result;
               end if;
               Advance (Pos);

            when others =>
               Kind := Node_Char;
               Ch := Pattern (Positive (Pos));
               Advance (Pos);
         end case;

         Atom_Fragment (Result.Expression, Kind, Max_States, Atom, Ch, Class);
         if Atom.Start = No_State then
            Result.Status := Too_Many_States;
            Result.Error_Offset := Relative_Offset (Pattern'First, Pos);
            return Result;
         end if;

         if Pos >= Positive'First
           and then Pos <= Nat (Pattern'Last)
           and then Pattern (Positive (Pos)) in '*' | '+' | '?'
         then
            Quantify
              (Result.Expression, Atom, Pattern (Positive (Pos)), Max_States, Ok, Quantified);
            Atom := Quantified;
            if not Ok then
               Result.Status := Too_Many_States;
               Result.Error_Offset := Relative_Offset (Pattern'First, Pos);
               return Result;
            end if;
            Advance (Pos);

            if Pos >= Positive'First
              and then Pos <= Nat (Pattern'Last)
              and then Pattern (Positive (Pos)) in '*' | '+' | '?'
            then
               Result.Status := Invalid_Quantifier;
               Result.Error_Offset := Relative_Offset (Pattern'First, Pos);
               return Result;
            end if;
         end if;

         if Have_Frag then
            Concat (Result.Expression, Current, Atom, Ok);
            if not Ok then
               Result.Status := Too_Many_States;
               Result.Error_Offset := Relative_Offset (Pattern'First, Pos);
               return Result;
            end if;
         else
            Current := Atom;
            Have_Frag := True;
         end if;
      end loop;

      New_State (Result.Expression, Node_Match, Max_States, Match);
      if Match = No_State then
         Result.Status := Too_Many_States;
         Result.Error_Offset := Pattern'Length;
         return Result;
      end if;

      Patch_To (Result.Expression, Current, Match);
      Result.Expression.Start := Current.Start;
      Result.Expression.Valid := True;
      Result.Status := Compile_Ok;
      Result.Error_Offset := 0;
      return Result;
   end Compile;

   function Is_Valid (Expression : Regexp) return Boolean is
     (Expression.Valid);

   procedure Consume_Step
     (Options : Match_Options;
      Steps   : in out Natural;
      Step_Limited : in out Boolean)
   is
   begin
      if Step_Limited then
         return;
      end if;

      if Steps >= Options.Max_Steps then
         Step_Limited := True;
      else
         Steps := Steps + 1;
      end if;
   end Consume_Step;

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
                        if Position = Nat (Text'First) then
                           Enqueue (Node.Out_1);
                        end if;

                     when Node_End_Line =>
                        if Position > Nat (Text'Last) then
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
   end Add_State;

   function Relative_First (Text : String; Position : Natural) return Natural is
     (Relative_Offset (Text'First, Position));

   function Relative_Last (Text : String; Position : Natural) return Natural is
     (Relative_Offset (Text'First, Position));

   function Whole_Word_Passes (Text : String; First, Last : Natural) return Boolean is
      Next_Pos : Natural;
      Left_Ok  : Boolean;
      Right_Ok : Boolean;
   begin
      Left_Ok := True;
      if First > Nat (Text'First) and then First > Positive'First then
         if First - 1 <= Nat (Text'Last) then
            Left_Ok := not Is_Word (Text (Positive (First - 1)));
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
         Right_Ok := not Is_Word (Text (Positive (Next_Pos)));
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

   function Run_From
     (Expression  : Regexp;
      Text        : String;
      Start_Pos   : Positive;
      Require_End : Boolean;
      Options     : Match_Options)
      return Match_Result
   is
      Current      : Active_Set := [others => False];
      Next         : Active_Set;
      Steps        : Natural := 0;
      Step_Limited : Boolean := False;
      Pos          : Natural := Start_Pos;
      Matched      : Boolean;
      Best_Matched : Boolean := False;
      Best_Last    : Natural := 0;
      Node         : State;
      Last         : Natural;
   begin
      if not Expression.Valid then
         return (Status => Invalid_Regexp, others => <>);
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
            if not Options.Whole_Word or else Whole_Word_Passes (Text, Start_Pos, Last) then
               Best_Matched := True;
               Best_Last := Last;
            end if;
         end if;

         exit when Pos > Nat (Text'Last);

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
                     if Equal_Chars (Node.Ch, Text (Positive (Pos)), Options.Case_Sensitive) then
                        Add_State (Expression, Next, Node.Out_1, Pos + 1, Text, Options, Steps, Step_Limited);
                     end if;

                  when Node_Any =>
                     if Text (Positive (Pos)) /= Character'Val (10)
                       and then Text (Positive (Pos)) /= Character'Val (13)
                     then
                        Add_State (Expression, Next, Node.Out_1, Pos + 1, Text, Options, Steps, Step_Limited);
                     end if;

                  when Node_Class =>
                     if Matches_Class (Node.Class, Text (Positive (Pos)), Options.Case_Sensitive) then
                        Add_State (Expression, Next, Node.Out_1, Pos + 1, Text, Options, Steps, Step_Limited);
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
         Advance (Pos);
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
   begin
      if not Expression.Valid then
         return (Status => Invalid_Regexp, others => <>);
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

   function Status_Image (Status : Compile_Status) return String is
   begin
      case Status is
         when Compile_Ok => return "compile ok";
         when Empty_Pattern => return "empty pattern";
         when Pattern_Too_Long => return "pattern too long";
         when Too_Many_States => return "too many states";
         when Invalid_Escape => return "invalid escape";
         when Unterminated_Class => return "unterminated class";
         when Empty_Class => return "empty class";
         when Invalid_Class_Range => return "invalid class range";
         when Invalid_Quantifier => return "invalid quantifier";
         when Quantifier_Without_Atom => return "quantifier without atom";
         when Unsupported_Syntax => return "unsupported syntax";
      end case;
   end Status_Image;

   function Status_Image (Status : Match_Status) return String is
   begin
      case Status is
         when Match_Ok => return "match ok";
         when No_Match => return "no match";
         when Match_Limit_Exceeded => return "match limit exceeded";
         when Invalid_Regexp => return "invalid regexp";
      end case;
   end Status_Image;

end Regexp;
