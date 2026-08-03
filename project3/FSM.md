```vhdl
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity FSM_counter is
    generic(
        upper : integer := 9;
        lower : integer := 0
    );
    port(
        rst : in  STD_LOGIC;
        clk : in  STD_LOGIC;
        q   : out STD_LOGIC_VECTOR(3 downto 0)
    );
end FSM_counter;

architecture Behavioral of FSM_counter is
    type counter_state is (counter1, counter2);
    signal now_state, next_state : counter_state;

    signal Qn, Qn_d : integer := lower;
begin

    process(clk, rst)
    begin
        if rst = '1' then
            now_state <= counter1;
        elsif rising_edge(clk) then
            now_state <= next_state;
        end if;
    end process;

    process(now_state, Qn)
    begin
        next_state <= now_state;

        case now_state is
            when counter1 =>
                if Qn >= upper then
                    next_state <= counter2;
                end if;

            when counter2 =>
                if Qn <= lower then
                    next_state <= counter1;
                end if;
        end case;
    end process;

    process(clk, rst)
    begin
        if rst = '1' then
            Qn <= lower;
        elsif rising_edge(clk) then
            Qn <= Qn_d;
        end if;
    end process;

    process(now_state, Qn)
    begin
        Qn_d <= Qn;

        case now_state is
            when counter1 =>
                if Qn >= upper then
                    Qn_d <= Qn - 1;
                else
                    Qn_d <= Qn + 1;
                end if;

            when counter2 =>
                if Qn <= lower then
                    Qn_d <= Qn + 1;
                else
                    Qn_d <= Qn - 1;
                end if;
        end case;
    end process;

    q <= std_logic_vector(to_unsigned(Qn, 4));

end Behavioral;
```

## 波形圖
<img width="1577" height="793" alt="image" src="https://github.com/user-attachments/assets/731e620e-0030-48f6-a5e3-d01dcbf02cfc" />

## AOV
<img width="901" height="231" alt="image" src="https://github.com/user-attachments/assets/42ccb7c5-4ab9-4787-8e59-fca9a0b39d80" />

## 架構圖
<img width="825" height="731" alt="image" src="https://github.com/user-attachments/assets/d27f7f94-b7cc-49f3-9782-3c7d246792dd" />
