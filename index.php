<?php

  error_reporting(E_ALL);
  ini_set('display_errors', TRUE);
  ini_set('display_startup_errors', TRUE);

  // Start the session for the curent user logging in
  session_start();

  // Inlude Class file
  require_once 'include/util_class.php';

  // Initialize the user class
  $user_class = new Logger();
  $dbh        = new DB();

if ( isset ( $_POST['submit'] ) ) {
  $username = ( $_POST['username'] );
  $password = ( $_POST['password'] );

  try {
    // $sql = "SELECT * FROM `users` WHERE `username` = '$username'";
    // $result = $dbh->query( $sql );
    // $result->setFetchMode( PDO::FETCH_ASSOC );
    // $result = $result->fetch();
    if ( $dbh ) {
      // Gather rowCount of data returned from DB
      if ( $sql = $dbh->connect_db()->query( "SELECT * FROM `users` WHERE `username` = '$username'" ) ) {
        $num_rows = $sql->rowCount();
      } else {
        $user_class->log_message ( "[Login] Unable to query for current user list", 3, "user_login" );
      }

      // Query for all users with the matching username in the users table
      if ( !$matching_users = $sql->fetchAll() ) { $user_class->log_message ( "[Login] Unable to query for users matching requested user: {$username}", 3, "user_login" ); }

    } else {
      $user_class->log_message ( "[Login] Unable to connect to MySQL Database", 3, "user_login" );
    }

  } catch ( PDOException $e ) {
    die ( $user_class->log_message ( "Could not connect to the database Storm:" . $e->getMessage() . "<br/>", 3, "user_login" ) );
  }


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
        $user_class->log_message ( "[Login] Session set for {$_SESSION['user']}", 1, "user_login" );
        header( "location: home.php" ); // redirects user to the authenticated home page
      }
    } else {
      $user_class->log_message ( "[Login] Incorrect password was provided for {$username}", 2, "user_login" );
      print '<script>alert( "Incorrect Password!" );</script>';
      print '<script>window.location.assign( "index.php" );</script>';
    }

  } else {
    $user_class->log_message ( "[Login] Can't locate user in database -> user: {$username}", 2, "user_login" );
    print '<script>alert( "User does not exist!" );</script>';
    print '<script>window.location.assign( "index.php" );</script>';
  }
}

?>

<html>
<head>
  <title>Storm</title>

  <!-- CDN'S -->
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css">
  <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.1.1/jquery.min.js"></script>
  <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js"></script>
  <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js" integrity="sha384-Tc5IQib027qvyjSMfHjOMaLkfuWVxZxUPnCJA7l2mCWNIpG9mGCD8wGNIcPD7Txa" crossorigin="anonymous"></script>
  <link rel="stylesheet" href="include/index.css">

</head>

<body>

<div class="container">
    <div class="row">
      <div class="col-md-6 col-md-offset-3">
        <div class="panel panel-login">
          <div class="panel-heading">
            <div class="row">
              <div class="col-xs-12">
                <a href="#" class="active" id="login-form-link">Login</a>
              </div>
            </div>
            <hr>
          </div>
          <div class="panel-body">
            <div class="row">
              <div class="col-lg-12">
                <form id="login-form" action="index.php" method="post" role="form" style="display: block;">
                  <div class="form-group">
                    <input type="text" name="username" id="username" tabindex="1" class="form-control" placeholder="Username" value="">
                  </div>
                  <div class="form-group">
                    <input type="password" name="password" id="password" tabindex="2" class="form-control" placeholder="Password">
                  </div>
                  <div class="form-group text-center">
                    <input type="checkbox" tabindex="3" class="" name="remember" id="remember">
                    <label for="remember"> Remember Me</label>
                  </div>
                  <div class="form-group">
                    <div class="row">
                      <div class="col-sm-6 col-sm-offset-3">
                        <input type="submit" name="submit" id="submit" tabindex="4" class="form-control btn btn-login" value="Log In">
                      </div>
                    </div>
                  </div>
                  <div class="form-group">
                    <div class="row">
                      <div class="col-lg-12">
                        <div class="text-center">
                          <a href="http://phpoll.com/recover" tabindex="5" class="forgot-password">Forgot Password?</a>
                        </div>
                      </div>
                    </div>
                  </div>
                </form>
                <form id="register-form" action="register.php" method="post" role="form" style="display: none;">
                  <div class="form-group">
                    <input type="text" name="username" id="username" tabindex="1" class="form-control" placeholder="Username" value="">
                  </div>
                  <div class="form-group">
                    <input type="email" name="email" id="email" tabindex="1" class="form-control" placeholder="Email Address" value="">
                  </div>
                  <div class="form-group">
                    <input type="password" name="password" id="password" tabindex="2" class="form-control" placeholder="Password">
                  </div>
                  <div class="form-group">
                    <input type="password" name="confirm-password" id="confirm-password" tabindex="2" class="form-control" placeholder="Confirm Password">
                  </div>
                  <div class="form-group">
                    <div class="row">
                      <div class="col-sm-6 col-sm-offset-3">
                        <input type="submit" name="register-submit" id="register-submit" tabindex="4" class="form-control btn btn-register" value="Register Now">
                      </div>
                    </div>
                  </div>
                </form>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>

</body>
</html>
