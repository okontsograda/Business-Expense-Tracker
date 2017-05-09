<?php
  // Load Class file
  require_once 'include/util_class.php';
  
  // Instantiate the variable to use with the User Class
  $user_class = new Logger();

  session_start();
  if ( session_destroy() ) {
    $user_class->log_message ( "[Logout] Session detroyed for {$_SESSION['user']}", 1, "user_login" );
    header( "location: index.php" );
  } else {
    $user_class->log_message ( "[Logout] Error encountered with destroying session for {$_SESSION['user']}", 3, "user_login" );
  }

?>
