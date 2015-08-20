#!/usr/bin/env python
#
# tournament.py -- implementation of a Swiss-system tournament
#

import psycopg2


def connect():
    """Connect to the PostgreSQL database.  Returns a database connection."""
    return psycopg2.connect("dbname=tournament")


def deleteMatches():
    """Remove all the match records from the database."""
    conn = connect()
    c = conn.cursor()
    c.execute("delete from match;")
    conn.commit()
    conn.close()


def deletePlayers():
    """Remove all the player records from the database."""
    conn = connect()
    c = conn.cursor()
    c.execute("delete from match;")  # necessary in order to delete players
    c.execute("delete from player;")
    conn.commit()
    conn.close()


def countPlayers():
    """Returns the number of players currently registered."""
    conn = connect()
    c = conn.cursor()
    c.execute("select count(*) from player;")
    count = c.fetchone()[0]
    conn.commit()
    conn.close()
    return count


def registerPlayer(name):
    """Adds a player to the tournament database.

    The database assigns a unique serial id number for the player.  (This
    should be handled by your SQL database schema, not in your Python code.)

    Args:
      name: the player's full name (need not be unique).
    """
    conn = connect()
    c = conn.cursor()
    c.execute("insert into player (name) values (%(name)s); ", {'name': name})
    conn.commit()
    conn.close()


def playerStandings():
    """Returns a list of the players and their win records, sorted by wins.

    The first entry in the list should be the player in first place, or a
    player tied for first place if there is currently a tie.

    Returns:
      A list of tuples, each of which contains (id, name, wins, matches):
        id: the player's unique id (assigned by the database)
        name: the player's full name (as registered)
        wins: the number of matches the player has won
        matches: the number of matches the player has played
    """
    conn = connect()
    c = conn.cursor()
    c.execute("""select id, name, wins, matches from standings""")
    standings = c.fetchall()
    conn.commit()
    conn.close()
    return standings

def extendedPlayerStandings():
    """Returns a list of the players and their win records, sorted by wins.

    The first entry in the list should be the player in first place, or a
    player tied for first place if there is currently a tie.

    Returns:
      A list of tuples, each of which contains (id, name, wins, matches):
        id: the player's unique id (assigned by the database)
        name: the player's full name (as registered)
        wins: the number of matches the player has won
        matches: the number of matches the player has played
        score: the total score of the player
        all_opps_wins: the omw (Opponent Match Wins) is the sum of all winns 
            of the players opponents, this is used for ranking in case of 
            equal score.
    """
    conn = connect()
    c = conn.cursor()
    c.execute("""select id, name, wins, matches, score, all_opps_wins
        from standings""")
    standings = c.fetchall()
    conn.commit()
    conn.close()
    return standings


def reportMatch(winner, loser):
    """Records the outcome of a single match between two players.

    Args:
      winner:  the id number of the player who won
      loser:  the id number of the player who lost
    """
    conn = connect()
    c = conn.cursor()
    c.execute(
        """insert into match (round_id, p1_id, p2_id, match_datetime,
            played, won_player_id, p1_score, p2_score) values
            (1, %(id1)s, %(id2)s, CURRENT_TIMESTAMP, true, %(id1)s, 3, 0);""",
        {'id1': winner, 'id2': loser})
    conn.commit()
    conn.close()

def reportTie(player1, player2):
    """Records the a single match between two players in case of a tie

    Args:
      player1:  the id number of the first player
      player2:  the id number of the second player
    """
    conn = connect()
    c = conn.cursor()
    c.execute(
        """insert into match (round_id, p1_id, p2_id, match_datetime,
            played, won_player_id, p1_score, p2_score) values
            (1, %(id1)s, %(id2)s, CURRENT_TIMESTAMP, true, null, 1, 1);""",
        {'id1': player1, 'id2': player2})
    conn.commit()
    conn.close()


def swissPairings():
    """Returns a list of pairs of players for the next round of a match.

    Assuming that there are an even number of players registered, each player
    appears exactly once in the pairings. Each player is paired with another
    player with an equal or nearly-equal win record, that is, a player adjacent
    to him or her in the standings.

    Returns:
      A list of tuples, each of which contains (id1, name1, id2, name2)
        id1: the first player's unique id
        name1: the first player's name
        id2: the second player's unique id
        name2: the second player's name
    """
    conn = connect()
    c = conn.cursor()
    c.execute("""select id1, name1, id2, name2 from simple_pairings as p;""")
    pairings = c.fetchall()
    conn.commit()
    conn.close()
    return pairings
