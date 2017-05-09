<?php

error_reporting(E_ALL);
ini_set('display_errors', TRUE);
ini_set('display_startup_errors', TRUE);

?>

<html>
  <head>
    <title> Storm User Register </title>
  </head>

  <body>
    <h2>Registration</h2>

    <a href="index.php">Login</a><br/><br/>

    <form action="register.php" method="POST">
      Enter Username: <input type="text" name="username" required="required" /> <br/>
      Enter Password: <input type="password" name="password" required="required" /> <br/>
      <input type="submit" value="register" name="registerUser"/>
    </form>
  </body>

</html>

<?php

  if ( isset ( $_POST['registerUser'] ) ) {
    $username = ( $_POST['username'] );
    $password = ( $_POST[ 'password' ] );
    $bool = true;
    logger( "[register] Username to register: {$username}", 1 );

    $dbh = new PDO("mysql:host=localhost;dbname=Storm", 'root', 'root' );

    $result = $dbh->query ( "SELECT * FROM `users`" )->fetchAll();
    // Display all rows from query
    foreach ( $result as $row ) {
      $table_users = $row[ 'username' ];

      // Check if there are any matching fields
      if ( $username == $table_users ) {
        $bool = false; // sets bool to false
          logger( "[register] Username {$username} already exists, cannot register", 2 );
        print '<script>alert( "Username has been taken!" ); </script>'; // Promts the user
        print '<script>window.location.assign( "register.php"); </script'; // redirects to register.php
      }
    }
    # check if bool is true
    if ( $bool ) {
      $insert_new_user = $dbh->query( "INSERT INTO `users` (`username`, `password` ) VALUES ( '$username', '$password' )" );
      if ( isset ( $insert_new_user ) ) {
          logger ( "[register] added new user to system -- User: {$username}", 1 );
        print '<script>alert( "Successfully Registered!" );</script>'; // Prompts user
        print '<script>window.location.assign( "login.php" );</script>'; // redirects to register.php
      }
    }

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
