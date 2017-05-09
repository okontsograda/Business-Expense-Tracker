<?php

  class DB {

    public function dbConnect( $db_name ) {
      $host       = 'localhost';
      $user       = 'root';
      $password   = 'root';


      try {
        $db = new PDO ( "mysql:host=$host;
                         port=8889;
                         dbname=$db_name;
                         password=$pass" );
      } catch ( Exception $e ) {
        return $e->getMessage();
      }
      return $db;
    }

  }

?>
