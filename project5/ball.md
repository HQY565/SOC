````vhdl
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pingpong_top is
    port(
        clk          : in  std_logic;
        rst          : in  std_logic;
        btn_l        : in  std_logic;
        btn_r        : in  std_logic;
        led_out      : out std_logic_vector(7 downto 0)
    );
end pingpong_top;

architecture Behavioral of pingpong_top is
    constant DIV_CNT     : integer := 2000000; 
    
    signal div_counter   : integer range 0 to DIV_CNT - 1 := 0;
    signal slow_clk      : std_logic := '0';
    
    signal ball_reg      : std_logic_vector(9 downto 0);
    signal dir           : std_logic;
    signal score_l       : unsigned(3 downto 0);
    signal score_r       : unsigned(3 downto 0);
    
    type state_type is (WAIT_SERVE, PLAYING, SHOW_SCORE);
    signal current_state : state_type;
    signal delay_cnt     : integer range 0 to 10;
begin

    process(clk, rst)
    begin
        if rst = '1' then
            div_counter <= 0;
        elsif rising_edge(clk) then
            if div_counter = DIV_CNT - 1 then
                div_counter <= 0;
            else
                div_counter <= div_counter + 1;
            end if;
        end if;
    end process;

    process(clk, rst)
    begin
        if rst = '1' then
            slow_clk <= '0';
        elsif rising_edge(clk) then
            if div_counter = DIV_CNT - 1 then
                slow_clk <= '1'; 
            else
                slow_clk <= '0'; 
            end if;
        end if;
    end process;

    process(clk, rst)
    begin
        if rst = '1' then
            current_state <= WAIT_SERVE;
        elsif rising_edge(clk) then
            if slow_clk = '1' then
                case current_state is
                    when WAIT_SERVE =>
                        if (ball_reg(8) = '1' and btn_l = '1') or (ball_reg(1) = '1' and btn_r = '1') then
                            current_state <= PLAYING;
                        end if;
                    when PLAYING =>
                        if dir = '0' and (ball_reg(1) = '1' or ball_reg(0) = '1') and btn_r = '1' then
                            current_state <= PLAYING;
                        elsif dir = '1' and (ball_reg(9) = '1' or ball_reg(8) = '1') and btn_l = '1' then
                            current_state <= PLAYING;
                        elsif (dir = '0' and ball_reg(0) = '1') or (dir = '0' and ball_reg(1) = '0' and ball_reg(0) = '0' and btn_r = '1') then
                            current_state <= SHOW_SCORE;
                        elsif (dir = '1' and ball_reg(9) = '1') or (dir = '1' and ball_reg(9) = '0' and ball_reg(8) = '0' and btn_l = '1') then
                            current_state <= SHOW_SCORE;
                        end if;
                    when SHOW_SCORE =>
                        if delay_cnt = 10 then
                            current_state <= WAIT_SERVE;
                        end if;
                end case;
            end if;
        end if;
    end process;
    
    process(clk, rst)
    begin
        if rst = '1' then
            ball_reg <= "0100000000";
        elsif rising_edge(clk) then
            if slow_clk = '1' then
                if current_state = SHOW_SCORE and delay_cnt = 10 then
                    if score_l > score_r then
                        ball_reg <= "0100000000";
                    else
                        ball_reg <= "0000000010";
                    end if;
                elsif current_state = PLAYING then
                    if dir = '0' and (ball_reg(1) = '1' or ball_reg(0) = '1') and btn_r = '1' then
                        ball_reg <= ball_reg(8 downto 0) & '0';
                    elsif dir = '1' and (ball_reg(9) = '1' or ball_reg(8) = '1') and btn_l = '1' then
                        ball_reg <= '0' & ball_reg(9 downto 1);
                    elsif (dir = '0' and ball_reg(0) = '1') or (dir = '0' and ball_reg(1) = '0' and ball_reg(0) = '0' and btn_r = '1') then
                        ball_reg <= "0000000010"; 
                    elsif (dir = '1' and ball_reg(9) = '1') or (dir = '1' and ball_reg(9) = '0' and ball_reg(8) = '0' and btn_l = '1') then
                        ball_reg <= "0100000000";
                    elsif dir = '0' then
                        ball_reg <= '0' & ball_reg(9 downto 1);
                    else
                        ball_reg <= ball_reg(8 downto 0) & '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(clk, rst)
    begin
        if rst = '1' then
            dir <= '0';
        elsif rising_edge(clk) then
            if slow_clk = '1' then
                if current_state = WAIT_SERVE then
                    if ball_reg(8) = '1' and btn_l = '1' then 
                        dir <= '0';
                    elsif ball_reg(1) = '1' and btn_r = '1' then 
                        dir <= '1';
                    end if;
                elsif current_state = PLAYING then
                    if dir = '0' and (ball_reg(1) = '1' or ball_reg(0) = '1') and btn_r = '1' then 
                        dir <= '1';
                    elsif dir = '1' and (ball_reg(9) = '1' or ball_reg(8) = '1') and btn_l = '1' then 
                        dir <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(clk, rst)
    begin
        if rst = '1' then
            score_l <= (others => '0');
        elsif rising_edge(clk) then
            if slow_clk = '1' then
                if current_state = PLAYING then
                    if dir = '0' and (ball_reg(1) = '1' or ball_reg(0) = '1') and btn_r = '1' then
                        score_l <= score_l;
                    elsif (dir = '0' and ball_reg(0) = '1') or (dir = '0' and ball_reg(1) = '0' and ball_reg(0) = '0' and btn_r = '1') then
                        score_l <= score_l + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(clk, rst)
    begin
        if rst = '1' then
            score_r <= (others => '0');
        elsif rising_edge(clk) then
            if slow_clk = '1' then
                if current_state = PLAYING then
                    if dir = '1' and (ball_reg(9) = '1' or ball_reg(8) = '1') and btn_l = '1' then
                        score_r <= score_r;
                    elsif (dir = '1' and ball_reg(9) = '1') or (dir = '1' and ball_reg(9) = '0' and ball_reg(8) = '0' and btn_l = '1') then
                        score_r <= score_r + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(clk, rst)
    begin
        if rst = '1' then
            delay_cnt <= 0;
        elsif rising_edge(clk) then
            if slow_clk = '1' then
                if current_state = SHOW_SCORE then
                    if delay_cnt < 10 then
                        delay_cnt <= delay_cnt + 1;
                    else
                        delay_cnt <= 0;
                    end if;
                else
                    delay_cnt <= 0;
                end if;
            end if;
        end if;
    end process;

    process(clk, rst)
    begin
        if rst = '1' then
            led_out <= (others => '0');
        elsif rising_edge(clk) then
            if current_state = SHOW_SCORE then
                led_out <= std_logic_vector(score_l) & std_logic_vector(score_r);
            else
                led_out <= ball_reg(8 downto 1);
            end if;
        end if;
    end process;

end Behavioral;
````
## 波形圖
<img width="1568" height="801" alt="image" src="https://github.com/user-attachments/assets/a7228ed1-bbbf-4e65-a67f-f072a2d7d624" />

## 架構圖
<img width="1429" height="496" alt="image" src="https://github.com/user-attachments/assets/46b11514-423d-4629-882c-aa518ff37452" />

## AOV
<img width="1023" height="214" alt="image" src="https://github.com/user-attachments/assets/87dac54e-8dcd-4416-86c8-098fbeb275a8" />

## FSM
<img width="1005" height="537" alt="image" src="https://github.com/user-attachments/assets/b793d6a2-7bac-4c7b-93d3-68096d2c4bdf" />

## break down
<img width="1378" height="390" alt="image" src="https://github.com/user-attachments/assets/f94c1598-76ec-4735-81d5-f17fbb8b14c3" />

## MSC
<img width="1309" height="346" alt="image" src="https://github.com/user-attachments/assets/9712da3b-6262-45b1-93f4-092d37b66077" />
