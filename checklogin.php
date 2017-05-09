<?php

  error_reporting(E_ALL);
  ini_set('display_errors', TRUE);
  ini_set('display_startup_errors', TRUE);

  session_start();

  $username = ( $_POST['username'] );
  $password = ( $_POST['password'] );

  try {
    $dbh = new PDO ( "mysql:host=localhost;dbname=RTA", 'root', 'Ol3g@123' );

    // $sql = "SELECT * FROM `users` WHERE `username` = '$username'";
    // $result = $dbh->query( $sql );
    // $result->setFetchMode( PDO::FETCH_ASSOC );
    // $result = $result->fetch();
    $sql = $dbh->query( "SELECT * FROM `users` WHERE `username` = '$username'" );
    $num_rows = $sql->rowCount();

  } catch ( PDOException $e ) {
    die ( "Could not connect to the database Storm:" . $e->getMessage() . "<br/>" );
  }

  // Query for all users with the matching username in the users table
  $matching_users = $sql->fetchAll();
  // Parse and assign the username and password values for the designated user
  foreach ( $matching_users as $user ) {
    $table_user     = $user['username'];
    $table_password = $user['password'];
  }

  if ( $num_rows > 0 ) {
    // Check if there are any matching fields
    if ( ( $username == $table_user ) && ( $password == $table_password ) ) {
      if ( $password == $table_password ) {
        $_SESSION['user'] = $username; // set the username in a session. Becomes global variable
        logger ( "[login] session: {$_SESSION['user']} username: {$username} -> redirecting to home page", 1 );
        header( "location: home.php" ); // redirects user to the authenticated home page
      }
    } else {
      logger ( "[login] Incorrect password for {$username} -> password: {$password}", 1 );
      print '<script>alert( "Incorrect Password!" );</script>';
      print '<script>window.location.assign( "login.php" );</script>';
    }

  } else {
    logger ( "[login] Can't locate user -> user: {$username}", 1 );
    print '<script>alert( "User does not exist!" );</script>';
    print '<script>window.location.assign( "login.php" );</script>';
  }

  function logger($message, $value) {
    $TIMESTAMP    = date("D M j Y G:i:s");
    $valueINFO    = '  [INFO]';
    $valueWARNING = '[WARNING]';
    $valueERROR   = ' [ERROR]';
    $logFile      = 'register.log';

    if($value == 1) {
      // Set logging for INFO
      $message = $TIMESTAMP . $valueINFO . " " . $message . PHP_EOL;
    }

    if($value == 2) {
      // Set logging for WARNING
      $message = $TIMESTAMP . $valueWARNING . " " . $message . PHP_EOL;
    }

    if($value == 3) {
      $message = $TIMESTAMP . $valueERROR . " " . $message . PHP_EOL;
    }

    return file_put_contents($logFile, $message, FILE_APPEND);
  }

 ?>
