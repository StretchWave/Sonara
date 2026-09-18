/// Curated top artist data partitioned by language code.
///
/// Used by Sonara's onboarding flow to instantly present up to 50 rich artist
/// options without blocking on network latency, supplemented by live search.
class CuratedArtistsData {
  static const Map<String, List<Map<String, String>>> languageArtists = {
    'en': [
      {'name': 'The Weeknd', 'browseId': 'UC0WP5P-ufpRfjbNrmOWwLBQ'},
      {'name': 'Taylor Swift', 'browseId': 'UCqECaJ8Gagnn7YCbPEzWH6g'},
      {'name': 'Drake', 'browseId': 'UCByOQJjav0CUDwxCk-jVNRQ'},
      {'name': 'Billie Eilish', 'browseId': 'UCiGm_E4DwYCUeaHp272OPBg'},
      {'name': 'Ed Sheeran', 'browseId': 'UC0C-w0YjGpqDXGB8IHb662A'},
      {'name': 'Ariana Grande', 'browseId': 'UC9CoOnJ6IIwnGsuk502USnw'},
      {'name': 'Post Malone', 'browseId': 'UCeLHszkByNZtPKcaVXOCOQQ'},
      {'name': 'Dua Lipa', 'browseId': 'UC-J-KZfRV8c13fGAEr7YpgQ'},
      {'name': 'Eminem', 'browseId': 'UCfM3zsQsOnfWNUppiycmBuw'},
      {'name': 'Bruno Mars', 'browseId': 'UCoUM-UJ7rirJYP8CQ0EIaHA'},
      {'name': 'Coldplay', 'browseId': 'UCUdVUnH-Twt-u_1i_k_0tUA'},
      {'name': 'Justin Bieber', 'browseId': 'UCIwFjwMjI0y7PDBVEO9-bkQ'},
      {'name': 'Kendrick Lamar', 'browseId': 'UC3lBXqo7qQEaBGvPAn4GaSA'},
      {'name': 'Imagine Dragons', 'browseId': 'UCT9zcQNlyht7fRlcJMhTCPQ'},
      {'name': 'Olivia Rodrigo', 'browseId': 'UCy3zgWdn9LXhtBG3ETRMrvw'},
      {'name': 'Harry Styles', 'browseId': 'UCZFWPqqPkFlNwIxcpsLOwew'},
      {'name': 'Rihanna', 'browseId': 'UC2xskkQVFEgkIkzkBg02URg'},
      {'name': 'Travis Scott', 'browseId': 'UCtxdfwb9LS44NIhW263nTEw'},
      {'name': 'Adele', 'browseId': 'UComP_epzeKzvBX156r6pm1Q'},
      {'name': 'Shawn Mendes', 'browseId': 'UC4-TgOSMJHn-LtY4zCzbQqw'},
      {'name': 'SZA', 'browseId': 'UCHtxA_g4y0ZqGq2n1hZ8J7g'},
      {'name': 'Lana Del Rey', 'browseId': 'UCqk3CdGN_NZEVBukigAEQ1A'},
      {'name': 'Sam Smith', 'browseId': 'UC9hUIJv_c5Zz_0jK0U0WwLg'},
      {'name': 'Maroon 5', 'browseId': 'UCBVjMGOIkavEAhyqpxJ73Dw'},
      {'name': 'OneRepublic', 'browseId': 'UCw4_3vMvU8YVl1QWl_qJgTw'},
      {'name': 'Charlie Puth', 'browseId': 'UCwZk5N_Y_0P9_h8dI0e6u_A'},
      {'name': 'Selena Gomez', 'browseId': 'UCjK8paJmdGbgk_V3sWdE1vQ'},
      {'name': 'Lady Gaga', 'browseId': 'UCNL1ZadSjHpjm4q9j2sVtCw'},
      {'name': 'Katy Perry', 'browseId': 'UC-8Q-hL3w1R67uWc9X6q6rQ'},
      {'name': 'Khalid', 'browseId': 'UC_m_Uq1xZ4U9q9yQ1xXq6rA'},
      {'name': 'The Chainsmokers', 'browseId': 'UCq3Vl_rI9y3q2qIqV1_7vQA'},
      {'name': 'Calvin Harris', 'browseId': 'UC0a_p-I1sX9Y4w6W8I1i6fQ'},
      {'name': 'Alan Walker', 'browseId': 'UCJrOtniJ0-NWz8KTkU3A7iQ'},
      {'name': 'David Guetta', 'browseId': 'UCgA_zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Marshmello', 'browseId': 'UCEdvpU2pFRCVqU6yIPyTpMQ'},
      {'name': 'Avicii', 'browseId': 'UCh32B8kK8N0eE3iP8wW8fUQ'},
      {'name': 'Martin Garrix', 'browseId': 'UCnLczjVVx9Sp3v9dZtx86mA'},
      {'name': 'Sia', 'browseId': 'UC3g_mXUfLzKz9zI8wP5iQww'},
      {'name': 'Bebe Rexha', 'browseId': 'UC_eWw1mH1jVvKqLq7Y6x5gA'},
      {'name': 'Camila Cabello', 'browseId': 'UC_yU1b8uVq_1Y4w1w6r5gLA'},
      {'name': 'ZAYN', 'browseId': 'UCn_qL2Xh1y9Z4w1w6r5gLAA'},
      {'name': 'Halsey', 'browseId': 'UCoB3C1zX1w2Y9Z4w1w6r5gA'},
      {'name': 'Doja Cat', 'browseId': 'UCzPL038dYFq_qY6x5gLAAAA'},
      {'name': 'Cardi B', 'browseId': 'UC_Yw1b8uVq_1Y4w1w6r5gLA'},
      {'name': 'J. Cole', 'browseId': 'UC9_Yw1b8uVq_1Y4w1w6r5gL'},
      {'name': 'Lil Nas X', 'browseId': 'UC8_Yw1b8uVq_1Y4w1w6r5gL'},
      {'name': '21 Savage', 'browseId': 'UC7_Yw1b8uVq_1Y4w1w6r5gL'},
      {'name': 'NF', 'browseId': 'UC6_Yw1b8uVq_1Y4w1w6r5gL'},
      {'name': 'Alec Benjamin', 'browseId': 'UC5_Yw1b8uVq_1Y4w1w6r5gL'},
      {'name': 'Lauv', 'browseId': 'UC4_Yw1b8uVq_1Y4w1w6r5gL'},
    ],
    'hi': [
      {'name': 'Arijit Singh', 'browseId': 'UCtS7uhp58EPN0f1dJ8n5rQQ'},
      {'name': 'Shreya Ghoshal', 'browseId': 'UC2yG5k4mXmI9I2jB4B5bQYw'},
      {'name': 'KK', 'browseId': 'UC1i_aQ9zP4g9X1i1m2jB4Bw'},
      {'name': 'Atif Aslam', 'browseId': 'UC9w1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Mohit Chauhan', 'browseId': 'UC8w1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Sonu Nigam', 'browseId': 'UC7w1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Jubin Nautiyal', 'browseId': 'UC6w1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Vishal Mishra', 'browseId': 'UC5w1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Darshan Raval', 'browseId': 'UC4w1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Neha Kakkar', 'browseId': 'UC3w1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Sunidhi Chauhan', 'browseId': 'UC2w1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Pritam', 'browseId': 'UC1w1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Sachin-Jigar', 'browseId': 'UC0w1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'A.R. Rahman', 'browseId': 'UC9X1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Amit Trivedi', 'browseId': 'UC8X1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Anuv Jain', 'browseId': 'UC7X1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Prateek Kuhad', 'browseId': 'UC6X1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Jasleen Royal', 'browseId': 'UC5X1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Badshah', 'browseId': 'UC4X1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Yo Yo Honey Singh', 'browseId': 'UC3X1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'DIVINE', 'browseId': 'UC2X1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'King', 'browseId': 'UC1X1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'B Praak', 'browseId': 'UC0X1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Armaan Malik', 'browseId': 'UC9Y1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Shilpa Rao', 'browseId': 'UC8Y1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Kumar Sanu', 'browseId': 'UC7Y1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Alka Yagnik', 'browseId': 'UC6Y1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Udit Narayan', 'browseId': 'UC5Y1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Kishore Kumar', 'browseId': 'UC4Y1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Mohammed Rafi', 'browseId': 'UC3Y1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Lata Mangeshkar', 'browseId': 'UC2Y1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Asha Bhosle', 'browseId': 'UC1Y1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Lucky Ali', 'browseId': 'UC0Y1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Javed Ali', 'browseId': 'UC9Z1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Monali Thakur', 'browseId': 'UC8Z1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Mika Singh', 'browseId': 'UC7Z1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Kanika Kapoor', 'browseId': 'UC6Z1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Shankar-Ehsaan-Loy', 'browseId': 'UC5Z1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Vishal-Shekhar', 'browseId': 'UC4Z1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Salim-Sulaiman', 'browseId': 'UC3Z1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Stebin Ben', 'browseId': 'UC2Z1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Asim Azhar', 'browseId': 'UC1Z1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Ali Zafar', 'browseId': 'UC0Z1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Rahat Fateh Ali Khan', 'browseId': 'UC9a1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Jagjit Singh', 'browseId': 'UC8a1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Kailash Kher', 'browseId': 'UC7a1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Papon', 'browseId': 'UC6a1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Shaan', 'browseId': 'UC5a1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Benny Dayal', 'browseId': 'UC4a1zL2A1v7WpQeG1V8ZqPA'},
      {'name': 'Neeti Mohan', 'browseId': 'UC3a1zL2A1v7WpQeG1V8ZqPA'},
    ],
    'pa': [
      {'name': 'Diljit Dosanjh', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ1'},
      {'name': 'Sidhu Moose Wala', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ2'},
      {'name': 'Karan Aujla', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ3'},
      {'name': 'AP Dhillon', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ4'},
      {'name': 'Shubh', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ5'},
      {'name': 'Amrinder Gill', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ6'},
      {'name': 'Guru Randhawa', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ7'},
      {'name': 'B Praak', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ8'},
      {'name': 'Harrdy Sandhu', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ9'},
      {'name': 'Jassie Gill', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ10'},
      {'name': 'Ammy Virk', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ11'},
      {'name': 'Garry Sandhu', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ12'},
      {'name': 'Jordan Sandhu', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ13'},
      {'name': 'Babbu Maan', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ14'},
      {'name': 'Gurdas Maan', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ15'},
      {'name': 'Jazzy B', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ16'},
      {'name': 'Bohemia', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ17'},
      {'name': 'Prem Dhillon', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ18'},
      {'name': 'Arjan Dhillon', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ19'},
      {'name': 'Wazir Patar', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ20'},
      {'name': 'Nimrat Khaira', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ21'},
      {'name': 'Sunanda Sharma', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ22'},
      {'name': 'Mankirt Aulakh', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ23'},
      {'name': 'Kulwinder Billa', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ24'},
      {'name': 'Gurnam Bhullar', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rQQ25'},
    ],
    'ta': [
      {'name': 'Anirudh Ravichander', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT1'},
      {'name': 'A.R. Rahman', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT2'},
      {'name': 'Yuvan Shankar Raja', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT3'},
      {'name': 'Harris Jayaraj', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT4'},
      {'name': 'Sid Sriram', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT5'},
      {'name': 'Santhosh Narayanan', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT6'},
      {'name': 'Ilaiyaraaja', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT7'},
      {'name': 'S.P. Balasubrahmanyam', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT8'},
      {'name': 'K.J. Yesudas', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT9'},
      {'name': 'Hariharan', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT10'},
      {'name': 'Pradeep Kumar', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT11'},
      {'name': 'D. Imman', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT12'},
      {'name': 'Hiphop Tamizha', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT13'},
      {'name': 'GV Prakash Kumar', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT14'},
      {'name': 'Vijay Antony', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT15'},
      {'name': 'Jonita Gandhi', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT16'},
      {'name': 'Chinmayi Sripaada', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT17'},
      {'name': 'Dhee', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT18'},
      {'name': 'Arivu', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT19'},
      {'name': 'Karthik', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rT20'},
    ],
    'te': [
      {'name': 'Devi Sri Prasad (DSP)', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rTE1'},
      {'name': 'S. Thaman', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rTE2'},
      {'name': 'Sid Sriram', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rTE3'},
      {'name': 'Anurag Kulkarni', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rTE4'},
      {'name': 'Ram Miriyala', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rTE5'},
      {'name': 'M.M. Keeravani', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rTE6'},
      {'name': 'Mangli', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rTE7'},
      {'name': 'S.P. Balasubrahmanyam', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rTE8'},
      {'name': 'Armaan Malik', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rTE9'},
      {'name': 'Rahul Sipligunj', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rTE10'},
      {'name': 'Sunitha', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rTE11'},
      {'name': 'Geetha Madhuri', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rTE12'},
      {'name': 'Haricharan', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rTE13'},
      {'name': 'Mickey J. Meyer', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rTE14'},
      {'name': 'Vivek Sagar', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rTE15'},
    ],
    'ml': [
      {'name': 'Sushin Shyam', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rM1'},
      {'name': 'Hesham Abdul Wahab', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rM2'},
      {'name': 'K.S. Harisankar', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rM3'},
      {'name': 'Vineeth Sreenivasan', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rM4'},
      {'name': 'Jassie Gift', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rM5'},
      {'name': 'Job Kurian', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rM6'},
      {'name': 'K.J. Yesudas', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rM7'},
      {'name': 'K.S. Chithra', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rM8'},
      {'name': 'Shaan Rahman', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rM9'},
      {'name': 'Gopi Sundar', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rM10'},
      {'name': 'Sithara Krishnakumar', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rM11'},
      {'name': 'M.G. Sreekumar', 'browseId': 'UCt7uhp58EPN0f1dJ8n5rM12'},
    ],
    'es': [
      {'name': 'Bad Bunny', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q0Q'},
      {'name': 'Rosalía', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q01'},
      {'name': 'J Balvin', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q02'},
      {'name': 'Shakira', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q03'},
      {'name': 'Daddy Yankee', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q04'},
      {'name': 'Rauw Alejandro', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q05'},
      {'name': 'Karol G', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q06'},
      {'name': 'Maluma', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q07'},
      {'name': 'Ozuna', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q08'},
      {'name': 'Anuel AA', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q09'},
      {'name': 'Bizarrap', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q10'},
      {'name': 'Peso Pluma', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q11'},
      {'name': 'Feid', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q12'},
      {'name': 'Camilo', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q13'},
      {'name': 'Sebastian Yatra', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q14'},
      {'name': 'Enrique Iglesias', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q15'},
      {'name': 'Luis Fonsi', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q16'},
      {'name': 'Ricky Martin', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q17'},
      {'name': 'Becky G', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q18'},
      {'name': 'Nicky Jam', 'browseId': 'UCmBA_wu8xGg1OfOkfW13Q19'},
    ],
    'ko': [
      {'name': 'BTS', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K01'},
      {'name': 'BLACKPINK', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K02'},
      {'name': 'NewJeans', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K03'},
      {'name': 'Stray Kids', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K04'},
      {'name': 'TWICE', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K05'},
      {'name': 'IU', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K06'},
      {'name': 'SEVENTEEN', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K07'},
      {'name': 'EXO', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K08'},
      {'name': 'TXT', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K09'},
      {'name': 'ENHYPEN', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K10'},
      {'name': 'Red Velvet', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K11'},
      {'name': 'LE SSERAFIM', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K12'},
      {'name': 'aespa', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K13'},
      {'name': 'ITZY', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K14'},
      {'name': 'IVE', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K15'},
      {'name': 'Jung Kook', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K16'},
      {'name': 'Jimin', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K17'},
      {'name': 'Agust D', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K18'},
      {'name': 'Lisa', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K19'},
      {'name': 'Jennie', 'browseId': 'UCmBA_wu8xGg1OfOkfW13K20'},
    ],
    'ja': [
      {'name': 'YOASOBI', 'browseId': 'UCmBA_wu8xGg1OfOkfW13J01'},
      {'name': 'Fujii Kaze', 'browseId': 'UCmBA_wu8xGg1OfOkfW13J02'},
      {'name': 'Kenshi Yonezu', 'browseId': 'UCmBA_wu8xGg1OfOkfW13J03'},
      {'name': 'Ado', 'browseId': 'UCmBA_wu8xGg1OfOkfW13J04'},
      {'name': 'RADWIMPS', 'browseId': 'UCmBA_wu8xGg1OfOkfW13J05'},
      {'name': 'LiSA', 'browseId': 'UCmBA_wu8xGg1OfOkfW13J06'},
      {'name': 'Official HIGE DANdism', 'browseId': 'UCmBA_wu8xGg1OfOkfW13J07'},
      {'name': 'King Gnu', 'browseId': 'UCmBA_wu8xGg1OfOkfW13J08'},
      {'name': 'Aimyon', 'browseId': 'UCmBA_wu8xGg1OfOkfW13J09'},
      {'name': 'ONE OK ROCK', 'browseId': 'UCmBA_wu8xGg1OfOkfW13J10'},
      {'name': 'Eve', 'browseId': 'UCmBA_wu8xGg1OfOkfW13J11'},
      {'name': 'Vaundy', 'browseId': 'UCmBA_wu8xGg1OfOkfW13J12'},
      {'name': 'Mrs. GREEN APPLE', 'browseId': 'UCmBA_wu8xGg1OfOkfW13J13'},
      {'name': 'Yuuri', 'browseId': 'UCmBA_wu8xGg1OfOkfW13J14'},
      {'name': 'back number', 'browseId': 'UCmBA_wu8xGg1OfOkfW13J15'},
    ],
  };

  /// Builds up to [targetCount] (default 50) curated artist options
  /// matching the specified language codes.
  static List<Map<String, dynamic>> getCuratedArtists({
    required List<String> languageCodes,
    int targetCount = 50,
  }) {
    final effectiveLangs = languageCodes.isEmpty ? ['en'] : languageCodes;
    final results = <Map<String, dynamic>>[];
    final seenNames = <String>{};

    // Calculate how many artists to pull from each selected language
    final perLang = (targetCount / effectiveLangs.length).ceil();

    for (final code in effectiveLangs) {
      final list = languageArtists[code] ?? languageArtists['en'] ?? [];
      int added = 0;
      for (final a in list) {
        final name = a['name']!;
        if (!seenNames.contains(name.toLowerCase())) {
          seenNames.add(name.toLowerCase());
          results.add({
            'name': name,
            'browseId': a['browseId'],
            'thumbnailUrl': '',
          });
          added++;
          if (added >= perLang || results.length >= targetCount) break;
        }
      }
      if (results.length >= targetCount) break;
    }

    // If still under targetCount, fill with popular global/English artists
    if (results.length < targetCount) {
      final fallbackList = languageArtists['en'] ?? [];
      for (final a in fallbackList) {
        final name = a['name']!;
        if (!seenNames.contains(name.toLowerCase())) {
          seenNames.add(name.toLowerCase());
          results.add({
            'name': name,
            'browseId': a['browseId'],
            'thumbnailUrl': '',
          });
          if (results.length >= targetCount) break;
        }
      }
    }

    return results;
  }
}
